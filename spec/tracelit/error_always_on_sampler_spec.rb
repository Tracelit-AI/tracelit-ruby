# frozen_string_literal: true

require "opentelemetry/sdk"
require_relative "../../lib/tracelit/error_always_on_sampler"

RSpec.describe Tracelit::ErrorAlwaysOnSampler do
  # Shared arguments for should_sample? — deterministic trace IDs avoid
  # flakiness with ratio-based sampling in boundary tests.
  let(:base_args) do
    {
      parent_context: OpenTelemetry::Context.empty,
      links:          [],
      name:           "test_span",
      kind:           :internal,
      attributes:     {},
    }
  end

  describe "#description" do
    subject(:sampler) { described_class.new(0.5) }

    it "identifies itself as ErrorAlwaysOnSampler" do
      expect(sampler.description).to include("ErrorAlwaysOnSampler")
    end

    it "embeds the inner TraceIdRatioBased description" do
      expect(sampler.description).to include("TraceIdRatioBased")
    end
  end

  describe "#should_sample?" do
    context "with rate 1.0 (always sample)" do
      subject(:sampler) { described_class.new(1.0) }

      it "returns a RECORD_AND_SAMPLE result (recording and sampled)" do
        result = sampler.should_sample?(**base_args, trace_id: Random.bytes(16))
        expect(result).to be_recording
        expect(result).to be_sampled
      end
    end

    context "with rate 0.0 (never sample)" do
      subject(:sampler) { described_class.new(0.0) }

      it "upgrades the DROP decision to RECORD_ONLY so processors still fire" do
        result = sampler.should_sample?(**base_args, trace_id: Random.bytes(16))
        expect(result).to be_recording
        expect(result).not_to be_sampled
      end

      it "returns RECORD_ONLY regardless of trace_id" do
        10.times do
          result = sampler.should_sample?(**base_args, trace_id: Random.bytes(16))
          expect(result).to be_recording
        end
      end
    end
  end
end
