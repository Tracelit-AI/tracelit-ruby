# frozen_string_literal: true

require_relative "../../lib/tracelit/version"
require_relative "../../lib/tracelit/rails_logger_bridge"

RSpec.describe Tracelit::RailsLoggerBridge::OTelLogger do
  let(:otel_logger) { instance_double("OTelLoggerBackend", on_emit: nil) }
  subject(:logger)  { described_class.new(otel_logger) }

  describe "SEVERITY_MAP constant" do
    it "maps DEBUG (0) → OTel 5" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[0]).to eq(5)
    end

    it "maps INFO (1) → OTel 9" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[1]).to eq(9)
    end

    it "maps WARN (2) → OTel 13" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[2]).to eq(13)
    end

    it "maps ERROR (3) → OTel 17" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[3]).to eq(17)
    end

    it "maps FATAL (4) → OTel 21" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[4]).to eq(21)
    end

    it "maps UNKNOWN (5) → OTel 1" do
      expect(Tracelit::RailsLoggerBridge::SEVERITY_MAP[5]).to eq(1)
    end
  end

  describe "#add" do
    it "emits with the correct OTel severity number" do
      logger.add(1, "hello")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(severity_number: 9)
      )
    end

    it "emits with the correct severity_text" do
      logger.add(2, "a warning")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(severity_text: "WARN")
      )
    end

    it "uses the message as the body" do
      logger.add(3, "something broke")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(body: "something broke")
      )
    end

    it "converts non-string messages to strings" do
      logger.add(1, 42)
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(body: "42")
      )
    end

    it "falls back to progname when message is nil" do
      logger.add(1, nil, "MyApp")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(body: "MyApp")
      )
    end

    it "evaluates the block when message is nil and no progname given" do
      logger.add(0) { "lazy body" }
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(body: "lazy body")
      )
    end

    it "includes a timestamp" do
      logger.add(1, "msg")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(timestamp: an_instance_of(Time))
      )
    end

    it "falls back to severity_number 9 for an unrecognised severity integer" do
      logger.add(99, "unusual")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(severity_number: 9)
      )
    end

    it "silently swallows exceptions raised by on_emit" do
      allow(otel_logger).to receive(:on_emit).and_raise(RuntimeError, "otel error")
      expect { logger.add(1, "msg") }.not_to raise_error
    end

    describe "re-entrancy guard (fix 10)" do
      it "does not emit a second record when called recursively on the same thread" do
        allow(otel_logger).to receive(:on_emit) do
          # Simulate OTel internals calling back into Rails.logger during emit
          logger.add(1, "recursive call")
        end

        logger.add(1, "original")

        # on_emit should only have been called once — the recursive call is suppressed
        expect(otel_logger).to have_received(:on_emit).once
      end

      it "clears the re-entrancy flag after the call completes" do
        logger.add(1, "first")
        logger.add(1, "second")

        expect(otel_logger).to have_received(:on_emit).twice
      end

      it "clears the re-entrancy flag even when on_emit raises" do
        call_count = 0
        allow(otel_logger).to receive(:on_emit) do
          call_count += 1
          raise RuntimeError, "otel exploded" if call_count == 1
        end

        logger.add(1, "first — raises inside on_emit")
        logger.add(1, "second — flag must be clear so this goes through")

        expect(call_count).to eq(2)
      end
    end
  end

  describe "#log" do
    it "is an alias for #add" do
      logger.log(0, "debug message")
      expect(otel_logger).to have_received(:on_emit).with(
        hash_including(severity_number: 5, body: "debug message")
      )
    end
  end

  describe "#close" do
    it "is a no-op" do
      expect { logger.close }.not_to raise_error
    end
  end
end
