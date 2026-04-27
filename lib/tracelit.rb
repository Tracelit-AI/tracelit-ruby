# frozen_string_literal: true

require_relative "tracelit/version"
require_relative "tracelit/configuration"
require_relative "tracelit/instrumentation"

module Tracelit
  class << self
    # Global configuration instance. Thread-safe after boot — configure
    # once in an initializer, read-only thereafter.
    def config
      @config ||= Configuration.new
    end

    # Yields the configuration object for block-style setup:
    #
    #   Tracelit.configure do |config|
    #     config.api_key      = "tl_live_abc123"
    #     config.service_name = "payments-api"
    #     config.environment  = "production"
    #     config.sample_rate  = 0.2
    #   end
    #
    def configure
      yield config
    end

    # Manually trigger SDK setup. Not needed for Rails — the Railtie
    # handles this automatically. Call explicitly for Sinatra/Rack:
    #
    #   Tracelit.start!
    #
    def start!
      Instrumentation.setup(config)
    end

    # Returns the OpenTelemetry tracer for this service.
    # Use for manual instrumentation of custom operations:
    #
    #   Tracelit.tracer.in_span("my_operation") do |span|
    #     span.set_attribute("order.id", order.id)
    #     do_work
    #   end
    #
    def tracer
      OpenTelemetry.tracer_provider.tracer(
        config.resolved_service_name,
        VERSION
      )
    end

    # Returns the Tracelit metrics interface for manual instrumentation:
    #
    #   Tracelit.metrics.counter("payments.processed").add(1,
    #     attributes: { "currency" => "USD" }
    #   )
    #
    def metrics
      Tracelit::Metrics
    end
  end
end

# Auto-require Railtie when Rails is present.
require_relative "tracelit/railtie" if defined?(::Rails::Railtie)
