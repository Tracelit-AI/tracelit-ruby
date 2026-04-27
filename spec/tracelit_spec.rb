# frozen_string_literal: true

# Loading the real SDK is safe here — requiring tracelit.rb only defines
# modules and methods; no OTel setup or network calls happen until
# Tracelit.start! is explicitly called (which is mocked in those tests).
require_relative "../lib/tracelit"

RSpec.describe Tracelit do
  before { described_class.instance_variable_set(:@config, nil) }

  describe ".config" do
    it "returns a Configuration instance" do
      expect(described_class.config).to be_a(Tracelit::Configuration)
    end

    it "memoises the same object across calls" do
      expect(described_class.config).to be(described_class.config)
    end
  end

  describe ".configure" do
    it "yields the config object" do
      yielded = nil
      described_class.configure { |c| yielded = c }
      expect(yielded).to be(described_class.config)
    end
  end

  describe ".metrics" do
    it "returns the Tracelit::Metrics module" do
      expect(described_class.metrics).to eq(Tracelit::Metrics)
    end
  end

  describe ".start!" do
    it "delegates to Instrumentation.setup with the current config" do
      allow(Tracelit::Instrumentation).to receive(:setup)
      described_class.start!
      expect(Tracelit::Instrumentation).to have_received(:setup).with(described_class.config)
    end
  end
end
