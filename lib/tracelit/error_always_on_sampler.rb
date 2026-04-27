# frozen_string_literal: true

module Tracelit
  # ErrorAlwaysOnSampler wraps a ratio-based sampler but upgrades DROP
  # decisions to RECORD_ONLY. This ensures span processors (including
  # ErrorSpanProcessor) fire on_end for ALL spans, even those outside
  # the sampling ratio.
  #
  # Without this, TraceIdRatioBased(0.0) returns DROP, which causes the
  # SDK to create NonRecordingSpans that bypass the processor pipeline
  # entirely — so ErrorSpanProcessor.on_end is never called.
  #
  # With RECORD_ONLY:
  # - Real spans are created and all processors fire
  # - BatchSpanProcessor ignores them (checks trace_flags.sampled? == false)
  # - ErrorSpanProcessor sees them and exports any that end in ERROR
  class ErrorAlwaysOnSampler
    Decision = OpenTelemetry::SDK::Trace::Samplers::Decision
    Result   = OpenTelemetry::SDK::Trace::Samplers::Result

    def initialize(rate)
      @inner = OpenTelemetry::SDK::Trace::Samplers.trace_id_ratio_based(rate)
    end

    def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
      result = @inner.should_sample?(
        trace_id: trace_id,
        parent_context: parent_context,
        links: links,
        name: name,
        kind: kind,
        attributes: attributes
      )

      if result.recording?
        result
      else
        # Upgrade DROP → RECORD_ONLY so processor pipeline fires
        Result.new(decision: Decision::RECORD_ONLY, tracestate: result.tracestate)
      end
    end

    def description
      "ErrorAlwaysOnSampler{#{@inner.description}}"
    end
  end
end
