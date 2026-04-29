# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"
require "opentelemetry-logs-sdk"
require "opentelemetry/exporter/otlp_logs"
require_relative "error_span_processor"
require_relative "error_always_on_sampler"
require_relative "rails_logger_bridge"
require_relative "metrics"

module Tracelit
  module Instrumentation
    SETUP_MUTEX = Mutex.new

    # Sets up the OpenTelemetry SDK with the Tracelit OTLP exporter.
    # Called once at application boot. Idempotent — safe to call multiple times.
    # Never raises — a misconfigured SDK must not crash the host application.
    def self.setup(config)
      SETUP_MUTEX.synchronize do
        return if @configured
        return unless config.enabled

        # Fix 1: Install a clean single-line error handler before any OTel SDK
        # calls so that internal OTel errors never dump raw stack traces into
        # the application's logs.
        OpenTelemetry.error_handler = lambda do |exception:, message:|
          msg = [message, exception&.message].compact.join(" — ")
          OpenTelemetry.logger.warn("[Tracelit] #{msg}")
        end

        # Fix 2/3: Soft validation — warn and bail out rather than raise.
        # An observability SDK must never crash the host application.
        errors = config.valid?
        if errors.any?
          OpenTelemetry.logger.warn("[Tracelit] disabled — #{errors.join(', ')}")
          return
        end

        OpenTelemetry::SDK.configure do |otel|
          # Resource attributes identify this service in Tracelit.
          # These populate the `resource` Map column on every telemetry row.
          otel.resource = OpenTelemetry::SDK::Resources::Resource.create(
            {
              OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME    => config.resolved_service_name,
              OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => config.environment,
              "telemetry.sdk.language" => "ruby",
              "telemetry.sdk.name"     => detect_framework,
              "telemetry.sdk.version"  => Tracelit::VERSION,
            }.merge(config.resource_attributes)
          )

          # Build the OTLP exporter once — shared by both processors
          exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
            endpoint: "#{config.endpoint}/v1/traces",
            headers: {
              "Authorization"  => "Bearer #{config.api_key}",
              "X-Service-Name" => config.resolved_service_name,
              "X-Environment"  => config.environment,
            }
          )

          # Primary processor: batches and exports sampled spans
          otel.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
          )

          # Error processor: always exports error spans regardless of
          # sampling decision — fires on_finish after status is known
          otel.add_span_processor(
            Tracelit::ErrorSpanProcessor.new(exporter)
          )

          # Auto-instrumentation: instruments Rails, Rack, ActiveRecord,
          # Action View, Net::HTTP, Faraday, Redis, Sidekiq, and more.
          # use_all() enables every installed instrumentation gem.
          otel.use_all
        end

        # Set sampler after configure — Configurator does not expose
        # sampler= in OTel SDK 1.x, must be set on the provider directly.
        # Skip at 1.0: the default AlwaysOn sampler is correct and we do not touch it.
        if config.sample_rate < 1.0
          OpenTelemetry.tracer_provider.sampler = error_always_on_sampler(config.sample_rate)
        end

        @configured = true
        @config     = config

        setup_logs(config)
        Tracelit::Metrics.setup(config)

        # Fix 5: Fork safety for Puma cluster mode and Unicorn.
        # Background threads (pollers) are killed in forked worker processes.
        # Process._fork (Ruby 3.1+) fires in the child after every fork so we
        # can restart pollers in each worker without touching the master.
        install_fork_hook(config)

        # Fix 9: Flush and shut down both providers gracefully on process exit
        # so the last metrics/traces batch is not lost during deploys.
        at_exit { shutdown }
      end
    end

    def self.reset!
      SETUP_MUTEX.synchronize do
        @configured = false
        @config     = nil
      end
    end

    def self.shutdown
      OpenTelemetry.tracer_provider.shutdown rescue nil
      OpenTelemetry.meter_provider.shutdown  rescue nil
    end

    private

    # Detects the web framework in use for the telemetry.sdk.name attribute.
    # This value appears as the `framework` column in the services table.
    def self.detect_framework
      return "rails"   if defined?(::Rails)
      return "sinatra" if defined?(::Sinatra)
      return "rack"    if defined?(::Rack)
      "ruby"
    end

    # Returns an ErrorAlwaysOnSampler wrapped in ParentBased so child spans
    # honour the parent's sampling decision. ErrorAlwaysOnSampler upgrades
    # DROP → RECORD_ONLY so that ErrorSpanProcessor.on_finish fires for all spans,
    # allowing error spans to be exported even outside the sampling ratio.
    def self.error_always_on_sampler(rate)
      OpenTelemetry::SDK::Trace::Samplers.parent_based(
        root: Tracelit::ErrorAlwaysOnSampler.new(rate)
      )
    end

    # Sets up the OTel Logs SDK: creates a LoggerProvider, attaches a
    # BatchLogRecordProcessor with an OTLP/HTTP exporter, registers it
    # globally, and installs the Rails.logger bridge.
    def self.setup_logs(config)
      logs_exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
        endpoint: "#{config.endpoint}/v1/logs",
        headers: {
          "Authorization"  => "Bearer #{config.api_key}",
          "X-Service-Name" => config.resolved_service_name,
          "X-Environment"  => config.environment,
        }
      )

      logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new(
        resource: OpenTelemetry.tracer_provider.resource
      )

      logger_provider.add_log_record_processor(
        OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(logs_exporter)
      )

      OpenTelemetry.logger_provider = logger_provider

      # Install the Rails.logger → OTel bridge after the provider is ready.
      # Called here (after Rails boot) so Rails.logger is already initialised.
      RailsLoggerBridge.install(logger_provider)
    rescue StandardError => e
      OpenTelemetry.logger.warn("[Tracelit] failed to set up logs: #{e.message}")
    end

    # Fix 5: Register a Process._fork hook (Ruby 3.1+) so that background
    # polling threads are restarted inside each forked Puma/Unicorn worker.
    # In the parent (pid != 0) nothing changes. In the child (pid == 0) we
    # restart the metric pollers so each worker reports its own stats.
    def self.install_fork_hook(config)
      return unless Process.respond_to?(:_fork)

      hook_module = Module.new do
        define_method(:_fork) do
          pid = super()
          if pid == 0
            # We are in the child — restart pollers for this worker
            Tracelit::Metrics.restart_pollers(config)
          end
          pid
        end
      end

      Process.singleton_class.prepend(hook_module)
    rescue StandardError => e
      OpenTelemetry.logger.warn("[Tracelit] could not install fork hook: #{e.message}")
    end
  end
end
