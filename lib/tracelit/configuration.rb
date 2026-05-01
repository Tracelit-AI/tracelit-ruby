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
      @api_key             = ENV["TRACELIT_API_KEY"]
      @service_name        = ENV["TRACELIT_SERVICE_NAME"]
      @environment         = ENV["TRACELIT_ENVIRONMENT"] || "production"
      @endpoint            = ENV["TRACELIT_ENDPOINT"]    || "https://ingest.tracelit.app"
      @sample_rate         = (ENV["TRACELIT_SAMPLE_RATE"] || "1.0").to_f
      @enabled             = ENV["TRACELIT_ENABLED"] != "false"
      @resource_attributes = {}
    end

    # Resolves the current commit SHA with zero developer friction.
    # Checks common CI/CD environment variables first, then falls back
    # to running `git rev-parse HEAD` in the project directory.
    def resolved_commit_sha
      return @resolved_commit_sha if defined?(@resolved_commit_sha)

      sha = ENV["COMMIT_SHA"] ||
            ENV["GIT_COMMIT_SHA"] ||
            ENV["GIT_COMMIT"] ||
            ENV["GITHUB_SHA"] ||
            ENV["HEROKU_SLUG_COMMIT"] ||
            ENV["SOURCE_VERSION"] ||        # Heroku alt
            ENV["RENDER_GIT_COMMIT"] ||     # Render
            ENV["FLY_APP_VERSION"] ||       # Fly.io
            ENV["RAILWAY_GIT_COMMIT_SHA"]   # Railway

      if sha.nil? || sha.empty?
        begin
          sha = `git rev-parse HEAD 2>/dev/null`.strip
          sha = nil if sha.empty?
        rescue StandardError
          sha = nil
        end
      end

      @resolved_commit_sha = sha
    end

    # Returns an array of human-readable error strings.
    # Empty array means the configuration is valid.
    # Never raises — callers decide whether to warn or abort.
    def valid?
      errors = []
      errors << "api_key is required" if api_key.nil? || api_key.to_s.empty?

      # Fix 3: check resolved_service_name so Rails apps that rely on automatic
      # name inference (module_parent_name) are not incorrectly flagged.
      if resolved_service_name == "unknown-service"
        errors << "service_name is required (set config.service_name or TRACELIT_SERVICE_NAME)"
      end

      unless sample_rate.between?(0.0, 1.0)
        errors << "sample_rate must be between 0.0 and 1.0 (got #{sample_rate})"
      end

      errors
    end

    # Kept for backwards compatibility. Previously raised ArgumentError;
    # now a no-op because an observability SDK must never crash the host app.
    # Use valid? to check for configuration errors programmatically.
    def validate!
      # no-op — see valid? for soft validation
    end

    # Infer service name from Rails application if not explicitly set.
    def resolved_service_name
      return service_name if service_name && !service_name.empty?
      return ::Rails.application.class.module_parent_name.underscore if defined?(::Rails)
      "unknown-service"
    end
  end
end
