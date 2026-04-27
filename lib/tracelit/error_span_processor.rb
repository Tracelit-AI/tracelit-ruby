# frozen_string_literal: true

module Tracelit
  # ErrorSpanProcessor ensures error spans are always exported
  # regardless of the sampling decision made at span creation time.
  #
  # How it works:
  # - ErrorAlwaysOnSampler returns RECORD_ONLY (not DROP) for unsampled spans,
  #   which ensures this processor's on_finish is called for every span
  # - On span finish, if the span has status ERROR, this processor forces it
  #   through the exporter directly, bypassing the BatchSpanProcessor
  # - BatchSpanProcessor ignores RECORD_ONLY spans (trace_flags.sampled? false)
  #   so there is no double-export for sampled error spans
  #
  # NOTE: opentelemetry-sdk 1.x uses on_finish (not on_end) as the hook name.
  class ErrorSpanProcessor
    def initialize(exporter)
      @exporter = exporter
    end

    def on_start(span, parent_context)
      # nothing to do at start
    end

    def on_finish(span)
      # Skip spans that are not in error — only intervene for errors
      return if span.status.ok?

      # Skip spans that were fully sampled — BatchSpanProcessor handles those.
      # This prevents double-export of error spans on traces that were sampled.
      return if span.context.trace_flags.sampled?

      # Force-export this error span regardless of sampling decision
      @exporter.export([span.to_span_data])
    rescue StandardError
      # Never let processor errors propagate to the application
    end

    def force_flush(timeout: nil)
      @exporter.force_flush(timeout: timeout)
    end

    def shutdown(timeout: nil)
      # Do not shut down the shared exporter here —
      # the BatchSpanProcessor owns its lifecycle
    end
  end
end
