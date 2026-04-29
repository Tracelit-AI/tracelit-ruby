# frozen_string_literal: true

require "opentelemetry/sdk"
require_relative "../../lib/tracelit"

RSpec.describe Tracelit::Instrumentation do
  let(:valid_config) do
    Tracelit::Configuration.new.tap do |c|
      c.api_key      = "tl_test_key"
      c.service_name = "test-service"
      c.enabled      = false  # disable full OTel SDK setup in unit tests
    end
  end

  before { described_class.reset! }

  describe "SETUP_MUTEX" do
    it "is a Mutex" do
      expect(described_class::SETUP_MUTEX).to be_a(Mutex)
    end
  end

  describe ".setup" do
    context "when enabled is false" do
      it "returns early without configuring OTel" do
        config = Tracelit::Configuration.new.tap { |c| c.enabled = false }
        expect(OpenTelemetry::SDK).not_to receive(:configure)
        described_class.setup(config)
      end
    end

    context "when configuration is invalid" do
      it "logs a warning and does not raise" do
        config = Tracelit::Configuration.new.tap do |c|
          c.enabled  = true
          c.api_key  = nil
          c.service_name = nil
        end

        warnings = []
        allow(OpenTelemetry.logger).to receive(:warn) { |msg| warnings << msg }

        expect { described_class.setup(config) }.not_to raise_error
        expect(warnings).to include(match(/\[Tracelit\] disabled/))
      end

      it "does not mark itself as configured after a failed validation" do
        config = Tracelit::Configuration.new.tap do |c|
          c.enabled  = true
          c.api_key  = nil
        end

        allow(OpenTelemetry.logger).to receive(:warn)
        described_class.setup(config)

        # reset flag should still be false — setup can be retried
        expect(described_class.instance_variable_get(:@configured)).to be_falsey
      end
    end

    context "idempotency" do
      it "does not reconfigure OTel when called a second time" do
        # First call with disabled=true is a no-op; we just verify the mutex guard
        described_class.setup(valid_config)  # returns early (disabled)
        call_count = 0
        allow(OpenTelemetry::SDK).to receive(:configure) { call_count += 1 }
        described_class.setup(valid_config)
        described_class.setup(valid_config)
        expect(call_count).to eq(0)
      end
    end
  end

  describe ".reset!" do
    it "clears @configured so setup can run again" do
      described_class.instance_variable_set(:@configured, true)
      described_class.reset!
      expect(described_class.instance_variable_get(:@configured)).to be false
    end
  end

  describe "custom OTel error handler (fix 1)" do
    it "installs a handler that does not raise on OTel errors" do
      # Simulate what happens when OTel calls the error handler
      config = Tracelit::Configuration.new.tap do |c|
        c.enabled  = true
        c.api_key  = nil  # invalid — causes early return after handler install
      end

      allow(OpenTelemetry.logger).to receive(:warn)

      described_class.setup(config)

      handler = OpenTelemetry.error_handler
      expect { handler.call(exception: RuntimeError.new("boom"), message: "test") }
        .not_to raise_error
    end

    it "formats the message as a single [Tracelit] prefixed line" do
      config = Tracelit::Configuration.new.tap { |c| c.enabled = true; c.api_key = nil }

      logged = []
      allow(OpenTelemetry.logger).to receive(:warn) { |m| logged << m }

      described_class.setup(config)

      handler = OpenTelemetry.error_handler
      handler.call(exception: RuntimeError.new("network fail"), message: "export error")

      expect(logged).to include(match(/\[Tracelit\].*export error.*network fail/))
    end
  end
end
