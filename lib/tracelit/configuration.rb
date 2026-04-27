# frozen_string_literal: true

module Tracelit
  class Configuration
    # Required
    attr_accessor :api_key

    # The name of this service as it will appear in Tracelit.
    # Defaults to the Rails app name if Rails is present.
    attr_accessor :service_name

    # Environment tag — production, staging, development, etc.
    attr_accessor :environment

    # Full URL of the Tracelit ingest endpoint.
    # Override only if self-hosting.
    attr_accessor :endpoint

    # Head-based sampling rate (0.0–1.0). Default: 1.0 (keep all traces).
    # Set to 0.1 to keep 10% of traces. Errors are always kept regardless.
    attr_accessor :sample_rate

    # Set false to disable all telemetry without removing the gem.
    # Useful for test environments.
    attr_accessor :enabled

    # Additional resource attributes appended to every span and log.
    # Hash of string keys and string values.
    attr_accessor :resource_attributes

    def initialize
      @api_key            = ENV["TRACELIT_API_KEY"]
      @service_name       = ENV["TRACELIT_SERVICE_NAME"]
      @environment        = ENV["TRACELIT_ENVIRONMENT"] || "production"
      @endpoint           = ENV["TRACELIT_ENDPOINT"]    || "https://ingest.tracelit.app"
      @sample_rate        = (ENV["TRACELIT_SAMPLE_RATE"] || "1.0").to_f
      @enabled            = ENV["TRACELIT_ENABLED"] != "false"
      @resource_attributes = {}
    end

    def validate!
      raise ArgumentError, "Tracelit.config.api_key is required" if api_key.nil? || api_key.empty?
      raise ArgumentError, "Tracelit.config.service_name is required" if service_name.nil? || service_name.empty?
      raise ArgumentError, "sample_rate must be between 0.0 and 1.0" unless sample_rate.between?(0.0, 1.0)
    end

    # Infer service name from Rails application if not explicitly set.
    def resolved_service_name
      return service_name if service_name && !service_name.empty?
      return ::Rails.application.class.module_parent_name.underscore if defined?(::Rails)
      "unknown-service"
    end
  end
end
