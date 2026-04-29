# frozen_string_literal: true

require_relative "../../lib/tracelit/version"
require_relative "../../lib/tracelit/configuration"

RSpec.describe Tracelit::Configuration do
  before do
    %w[
      TRACELIT_API_KEY
      TRACELIT_SERVICE_NAME
      TRACELIT_ENVIRONMENT
      TRACELIT_ENDPOINT
      TRACELIT_SAMPLE_RATE
      TRACELIT_ENABLED
    ].each { |k| ENV.delete(k) }
  end

  describe "#initialize" do
    it "reads api_key from TRACELIT_API_KEY" do
      ENV["TRACELIT_API_KEY"] = "tl_test_key"
      expect(described_class.new.api_key).to eq("tl_test_key")
    end

    it "defaults api_key to nil when the env var is absent" do
      expect(described_class.new.api_key).to be_nil
    end

    it "reads service_name from TRACELIT_SERVICE_NAME" do
      ENV["TRACELIT_SERVICE_NAME"] = "my-service"
      expect(described_class.new.service_name).to eq("my-service")
    end

    it "defaults service_name to nil when the env var is absent" do
      expect(described_class.new.service_name).to be_nil
    end

    it "defaults environment to 'production'" do
      expect(described_class.new.environment).to eq("production")
    end

    it "reads environment from TRACELIT_ENVIRONMENT" do
      ENV["TRACELIT_ENVIRONMENT"] = "staging"
      expect(described_class.new.environment).to eq("staging")
    end

    it "defaults endpoint to the Tracelit ingest URL" do
      expect(described_class.new.endpoint).to eq("https://ingest.tracelit.app")
    end

    it "reads endpoint from TRACELIT_ENDPOINT" do
      ENV["TRACELIT_ENDPOINT"] = "https://self-hosted.example.com"
      expect(described_class.new.endpoint).to eq("https://self-hosted.example.com")
    end

    it "defaults sample_rate to 1.0" do
      expect(described_class.new.sample_rate).to eq(1.0)
    end

    it "reads sample_rate from TRACELIT_SAMPLE_RATE" do
      ENV["TRACELIT_SAMPLE_RATE"] = "0.25"
      expect(described_class.new.sample_rate).to eq(0.25)
    end

    it "defaults enabled to true" do
      expect(described_class.new.enabled).to be true
    end

    it "disables when TRACELIT_ENABLED is 'false'" do
      ENV["TRACELIT_ENABLED"] = "false"
      expect(described_class.new.enabled).to be false
    end

    it "remains enabled for any value other than 'false'" do
      ENV["TRACELIT_ENABLED"] = "0"
      expect(described_class.new.enabled).to be true
    end

    it "initialises resource_attributes as an empty hash" do
      expect(described_class.new.resource_attributes).to eq({})
    end
  end

  describe "#valid?" do
    subject(:config) do
      described_class.new.tap do |c|
        c.api_key      = "tl_live_abc123"
        c.service_name = "test-service"
      end
    end

    it "returns an empty array when all required fields are valid" do
      expect(config.valid?).to be_empty
    end

    it "returns an error when api_key is nil" do
      config.api_key = nil
      expect(config.valid?).to include(match(/api_key is required/))
    end

    it "returns an error when api_key is empty" do
      config.api_key = ""
      expect(config.valid?).to include(match(/api_key is required/))
    end

    it "returns an error when resolved_service_name falls back to 'unknown-service'" do
      config.service_name = nil
      expect(config.valid?).to include(match(/service_name is required/))
    end

    it "returns an error when sample_rate is below 0.0" do
      config.sample_rate = -0.01
      expect(config.valid?).to include(match(/sample_rate must be between/))
    end

    it "returns an error when sample_rate is above 1.0" do
      config.sample_rate = 1.01
      expect(config.valid?).to include(match(/sample_rate must be between/))
    end

    it "accepts sample_rate of exactly 0.0" do
      config.sample_rate = 0.0
      expect(config.valid?).to be_empty
    end

    it "accepts sample_rate of exactly 1.0" do
      config.sample_rate = 1.0
      expect(config.valid?).to be_empty
    end

    it "never raises — always returns an array" do
      config.api_key = nil
      config.service_name = nil
      expect { config.valid? }.not_to raise_error
    end
  end

  describe "#validate!" do
    it "is a no-op and never raises" do
      config = described_class.new
      config.api_key      = nil
      config.service_name = nil
      config.sample_rate  = 99.0
      expect { config.validate! }.not_to raise_error
    end
  end

  describe "#resolved_service_name" do
    subject(:config) { described_class.new }

    it "returns the explicit service_name when set" do
      config.service_name = "explicit-name"
      expect(config.resolved_service_name).to eq("explicit-name")
    end

    it "falls back to 'unknown-service' when service_name is nil and Rails is absent" do
      config.service_name = nil
      expect(config.resolved_service_name).to eq("unknown-service")
    end

    it "falls back to 'unknown-service' when service_name is an empty string" do
      config.service_name = ""
      expect(config.resolved_service_name).to eq("unknown-service")
    end
  end
end
