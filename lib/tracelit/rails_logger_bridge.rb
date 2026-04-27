# frozen_string_literal: true

module Tracelit
  # RailsLoggerBridge adds an OpenTelemetry log emitter to Rails.logger
  # so that every Rails.logger call is also forwarded to the OTel
  # LoggerProvider and exported via OTLP to the Tracelit logs table.
  #
  # It works by broadcasting a lightweight Logger subclass (OTelLogger)
  # alongside the existing logger. In Rails 7.1+, Rails.logger is already
  # an ActiveSupport::BroadcastLogger, so we call broadcast_to directly.
  # In older setups we wrap it in a new BroadcastLogger.
  #
  # Severity mapping (OTel SeverityNumber spec):
  #   Rails DEBUG (0) → OTel 5  (SEVERITY_NUMBER_DEBUG)
  #   Rails INFO  (1) → OTel 9  (SEVERITY_NUMBER_INFO)
  #   Rails WARN  (2) → OTel 13 (SEVERITY_NUMBER_WARN)
  #   Rails ERROR (3) → OTel 17 (SEVERITY_NUMBER_ERROR)
  #   Rails FATAL (4) → OTel 21 (SEVERITY_NUMBER_FATAL)
  #   Rails UNKNOWN   → OTel 1  (SEVERITY_NUMBER_TRACE)
  module RailsLoggerBridge
    SEVERITY_MAP = [5, 9, 13, 17, 21, 1].freeze

    def self.install(logger_provider)
      return unless defined?(::Rails) && ::Rails.logger

      otel_logger = logger_provider.logger(
        name:    "rails",
        version: Tracelit::VERSION
      )

      otel_sink = OTelLogger.new(otel_logger)

      if ::Rails.logger.is_a?(ActiveSupport::BroadcastLogger)
        ::Rails.logger.broadcast_to(otel_sink)
      else
        ::Rails.logger = ActiveSupport::BroadcastLogger.new(
          ::Rails.logger,
          otel_sink
        )
      end
    rescue StandardError => e
      warn "Tracelit: failed to install Rails logger bridge: #{e.message}"
    end

    # OTelLogger is a Logger subclass whose add method emits an OTel LogRecord
    # instead of writing to an IO device. It is added as a broadcast target so
    # the original Rails logger output is preserved.
    #
    # The SDK Logger#on_emit defaults context: to OpenTelemetry::Context.current,
    # which automatically correlates the log record to the current active span
    # (trace_id + span_id) without any extra work here.
    class OTelLogger < ::Logger
      def initialize(otel_logger)
        # Discard output — this logger only emits OTel records
        super(File::NULL)
        @otel_logger = otel_logger
        # Accept all severities so we don't filter below the original logger
        self.level = ::Logger::DEBUG
      end

      def add(severity, message = nil, progname = nil)
        severity_number = SEVERITY_MAP[severity.to_i] || 9
        severity_text   = ::Logger::SEV_LABEL[severity.to_i] || "ANY"

        body = if message.nil?
          block_given? ? yield : progname
        else
          message
        end

        @otel_logger.on_emit(
          timestamp:       Time.now,
          severity_number: severity_number,
          severity_text:   severity_text,
          body:            body.to_s
        )
      rescue StandardError
        # Never let OTel errors surface to the application
      end
      alias_method :log, :add

      def close; end
    end
  end
end
