# frozen_string_literal: true

require "opentelemetry/metrics"
require "opentelemetry-metrics-sdk"
require "opentelemetry/exporter/otlp_metrics"

module Tracelit
  module Metrics
    # Sets up the OpenTelemetry MeterProvider with OTLP exporter.
    # Called once from Instrumentation.setup after trace setup.
    def self.setup(config)
      # Force delta temporality for all instruments. The SDK aggregation classes
      # (Sum, ExplicitBucketHistogram) read this env var at construction time;
      # there is no constructor keyword on MetricsExporter for this in v0.8.0.
      ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"] = "delta"

      exporter = OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(
        endpoint: "#{config.endpoint}/v1/metrics",
        headers: {
          "Authorization"  => "Bearer #{config.api_key}",
          "X-Service-Name" => config.resolved_service_name,
          "X-Environment"  => config.environment,
        }
      )

      reader = OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
        exporter: exporter,
        export_interval_millis: 60_000,
        export_timeout_millis:  10_000
      )

      provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(
        resource: OpenTelemetry.tracer_provider.resource
      )
      provider.add_metric_reader(reader)

      OpenTelemetry.meter_provider = provider

      @meter = provider.meter(
        config.resolved_service_name,
        version: Tracelit::VERSION
      )

      install_rails_subscriber       if defined?(::Rails)
      install_sidekiq_middleware      if defined?(::Sidekiq)
      install_connection_pool_poller  if defined?(::ActiveRecord)
      install_memory_poller
    rescue StandardError => e
      OpenTelemetry.logger.warn("Tracelit: failed to set up metrics: #{e.message}")
    end

    def self.meter
      @meter
    end

    # Exposes a counter for manual instrumentation in user code:
    #   Tracelit::Metrics.counter("orders.placed").add(1)
    def self.counter(name, description: "", unit: "")
      @meter&.create_counter(name,
        description: description,
        unit: unit
      )
    end

    def self.histogram(name, description: "", unit: "")
      @meter&.create_histogram(name,
        description: description,
        unit: unit
      )
    end

    def self.gauge(name, description: "", unit: "")
      @meter&.create_gauge(name,
        description: description,
        unit: unit
      )
    end

    # Subscribes to Rails process_action.action_controller to emit:
    #   http.server.request.count    — counter per request
    #   http.server.request.duration — histogram in milliseconds
    #   http.server.error.count      — counter for 5xx responses
    #   db.query.duration            — histogram for ActiveRecord time per request
    def self.install_rails_subscriber
      request_counter = @meter.create_counter(
        "http.server.request.count",
        description: "Total HTTP requests processed",
        unit: "{requests}"
      )

      duration_histogram = @meter.create_histogram(
        "http.server.request.duration",
        description: "HTTP request duration",
        unit: "ms"
      )

      error_counter = @meter.create_counter(
        "http.server.error.count",
        description: "Total HTTP 5xx responses",
        unit: "{errors}"
      )

      db_duration_histogram = @meter.create_histogram(
        "db.query.duration",
        description: "Database query duration",
        unit: "ms"
      )

      ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        payload = event.payload

        attrs = {
          "http.method"      => payload[:method].to_s,
          "http.route"       => payload[:path].to_s,
          "http.status_code" => payload[:status].to_s,
          "controller"       => payload[:controller].to_s,
          "action"           => payload[:action].to_s,
        }

        request_counter.add(1, attributes: attrs)
        duration_histogram.record(event.duration, attributes: attrs)

        error_counter.add(1, attributes: attrs) if payload[:status].to_i >= 500

        if payload[:db_runtime]
          db_duration_histogram.record(
            payload[:db_runtime].to_f,
            attributes: { "controller" => payload[:controller].to_s }
          )
        end
      rescue StandardError
        # Never let metric errors surface to the application
      end
    end

    # Installs a Sidekiq server middleware that emits per-job metrics.
    # Uses a dynamically defined class so the instrument references are
    # captured in the closure without global state.
    def self.install_sidekiq_middleware
      job_counter = @meter.create_counter(
        "sidekiq.job.count",
        description: "Total Sidekiq jobs processed",
        unit: "{jobs}"
      )

      job_duration = @meter.create_histogram(
        "sidekiq.job.duration",
        description: "Sidekiq job execution duration",
        unit: "ms"
      )

      job_error_counter = @meter.create_counter(
        "sidekiq.job.error.count",
        description: "Total Sidekiq jobs that raised an error",
        unit: "{jobs}"
      )

      _job_counter       = job_counter
      _job_duration      = job_duration
      _job_error_counter = job_error_counter

      middleware_class = Class.new do
        define_method(:call) do |_worker, msg, queue, &block|
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          error_raised = false

          begin
            block.call
          rescue StandardError
            error_raised = true
            raise
          ensure
            elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

            attrs = {
              "sidekiq.job.class" => msg["class"].to_s,
              "sidekiq.queue"     => queue.to_s,
              "sidekiq.status"    => error_raised ? "error" : "success",
            }

            _job_counter.add(1, attributes: attrs)
            _job_duration.record(elapsed_ms, attributes: attrs)
            _job_error_counter.add(1, attributes: attrs) if error_raised
          end
        end
      end

      Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.add middleware_class
        end
      end
    rescue StandardError => e
      warn "Tracelit: failed to install Sidekiq middleware: #{e.message}"
    end

    # Polls ActiveRecord connection pool stats every 30 seconds on a daemon
    # thread and records them as gauges. Does not require a live connection
    # at install time — errors during polling are silently retried next cycle.
    def self.install_connection_pool_poller
      pool_size = @meter.create_gauge(
        "db.connection_pool.size",
        description: "Maximum connections in the pool",
        unit: "{connections}"
      )

      pool_busy = @meter.create_gauge(
        "db.connection_pool.busy",
        description: "Connections currently checked out",
        unit: "{connections}"
      )

      pool_idle = @meter.create_gauge(
        "db.connection_pool.idle",
        description: "Connections available for checkout",
        unit: "{connections}"
      )

      pool_waiting = @meter.create_gauge(
        "db.connection_pool.waiting",
        description: "Threads waiting for a connection",
        unit: "{threads}"
      )

      thread = Thread.new do
        Thread.current[:tracelit_pool_poller] = true
        loop do
          sleep 30
          begin
            pool  = ActiveRecord::Base.connection_pool
            stat  = pool.stat
            attrs = { "db.system" => pool.pool_config.db_config.adapter.to_s }
            pool_size.record(stat[:size], attributes: attrs)
            pool_busy.record(stat[:busy], attributes: attrs)
            pool_idle.record(stat[:idle], attributes: attrs)
            pool_waiting.record(stat[:waiting], attributes: attrs)
          rescue StandardError
            # Pool may not be connected yet — retry next cycle
          end
        end
      end
      thread.abort_on_exception = false
      thread
    rescue StandardError => e
      warn "Tracelit: failed to install connection pool poller: #{e.message}"
    end

    # Polls process RSS memory every 60 seconds on a daemon thread using ps,
    # which works on both macOS (arm64-darwin) and Linux without /proc.
    def self.install_memory_poller
      memory_gauge = @meter.create_gauge(
        "process.memory.rss",
        description: "Process resident set size (RSS)",
        unit: "MB"
      )

      pid = Process.pid

      thread = Thread.new do
        Thread.current[:tracelit_memory_poller] = true
        loop do
          sleep 60
          begin
            rss_kb = `ps -o rss= -p #{pid} 2>/dev/null`.strip.to_i
            next if rss_kb == 0

            rss_mb = rss_kb / 1024.0
            memory_gauge.record(rss_mb, attributes: {
              "process.pid"     => pid.to_s,
              "process.runtime" => "ruby",
            })
          rescue StandardError
            # Ignore — ps may not be available in all environments
          end
        end
      end
      thread.abort_on_exception = false
      thread
    rescue StandardError => e
      warn "Tracelit: failed to install memory poller: #{e.message}"
    end
  end
end
