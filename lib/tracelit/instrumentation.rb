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
    # Sets up the OpenTelemetry SDK with the Tracelit OTLP exporter.
    # Called once at application boot. Idempotent — safe to call multiple times.
    def self.setup(config)
      return if @configured
      return unless config.enabled

      config.validate!

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
      setup_logs(config)
      Tracelit::Metrics.setup(config)
    end

    def self.reset!
      @configured = false
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
      OpenTelemetry.logger.warn("Tracelit: failed to set up logs: #{e.message}")
    end
  end
end
