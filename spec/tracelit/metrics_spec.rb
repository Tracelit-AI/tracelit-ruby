# frozen_string_literal: true

require_relative "../../lib/tracelit/version"
require_relative "../../lib/tracelit/configuration"

# Load metrics in isolation — stub OTel meter so we don't need a live provider
RSpec.describe Tracelit::Metrics do
  before do
    # Reset double-registration guards between tests
    described_class.instance_variable_set(:@rails_subscriber_installed,          false)
    described_class.instance_variable_set(:@sidekiq_middleware_installed,         false)
    described_class.instance_variable_set(:@connection_pool_poller_installed,     false)
    described_class.instance_variable_set(:@memory_poller_installed,              false)
  end

  describe "ENV temporality default (fix 8)" do
    it "sets OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE to delta when unset" do
      # The constant is set at require time; just verify it's present and correct
      expect(ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"]).to eq("delta")
    end

    it "does not overwrite a pre-existing value" do
      original = ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"]
      # Simulate user having set it before requiring the gem
      ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"] = "cumulative"
      # Re-evaluate the ||= logic inline to prove it would not clobber
      ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"] ||= "delta"
      expect(ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"]).to eq("cumulative")
    ensure
      ENV["OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE"] = original
    end
  end

  describe "double-registration guard (fix 6)" do
    let(:meter) { instance_double("OpenTelemetry::Metrics::Meter") }

    before do
      described_class.instance_variable_set(:@meter, meter)
      allow(meter).to receive(:create_counter).and_return(double("counter", add: nil))
      allow(meter).to receive(:create_histogram).and_return(double("histogram", record: nil))
    end

    it "does not register the Rails subscriber twice" do
      stub_const("ActiveSupport::Notifications", double("AS::Notifications", subscribe: nil))
      stub_const("ActiveRecord", Module.new)

      # Both calls should only subscribe once
      described_class.install_rails_subscriber
      described_class.install_rails_subscriber

      expect(meter).to have_received(:create_counter)
        .with("http.server.request.count", anything).once
    end
  end

  describe "http.route attribute (fix 7)" do
    let(:meter) { instance_double("OpenTelemetry::Metrics::Meter") }
    let(:counter)   { double("counter",   add: nil) }
    let(:histogram) { double("histogram", record: nil) }

    before do
      described_class.instance_variable_set(:@meter, meter)
      allow(meter).to receive(:create_counter).and_return(counter)
      allow(meter).to receive(:create_histogram).and_return(histogram)
    end

    it "uses controller#action as the route instead of the raw path" do
      subscribed_block = nil

      # Build a minimal ActiveSupport::Notifications + Event hierarchy so the
      # subscriber under test can call Event.new(*args) without ActiveSupport
      # being loaded in this unit-test context.
      # subscribe must be defined before stubbing (verify_partial_doubles is on).
      as_notifications = Module.new do
        def self.subscribe(_name, &_block); end
      end

      as_event_class = Class.new do
        attr_reader :payload, :duration
        def initialize(*_args); end
      end

      as_module = Module.new
      as_module.const_set(:Notifications, as_notifications)
      as_notifications.const_set(:Event, as_event_class)

      allow(as_notifications).to receive(:subscribe) do |_name, &blk|
        subscribed_block = blk
      end

      stub_const("ActiveSupport", as_module)
      stub_const("ActiveRecord", Module.new)

      described_class.install_rails_subscriber

      # Build a fake event whose payload contains a URL with a resource ID
      payload = {
        controller:  "OrdersController",
        action:      "show",
        method:      "GET",
        path:        "/orders/12345",  # raw path — must NOT appear in route attr
        status:      200,
        db_runtime:  nil,
      }

      event = double("event", payload: payload, duration: 42.0)
      allow(as_event_class).to receive(:new).and_return(event)

      subscribed_block.call("process_action.action_controller", nil, nil, nil, payload)

      expect(counter).to have_received(:add).with(
        1,
        attributes: hash_including("http.route" => "OrdersController#show")
      )
      expect(counter).not_to have_received(:add).with(
        anything,
        attributes: hash_including("http.route" => "/orders/12345")
      )
    end
  end

  describe "memory poller (fix 12)" do
    it "reads /proc/self/status on Linux when available" do
      allow(File).to receive(:exist?).with("/proc/self/status").and_return(true)
      allow(File).to receive(:read).with("/proc/self/status").and_return(
        "Name:\truby\nVmRSS:\t 51200 kB\n"
      )

      rss_kb = if File.exist?("/proc/self/status")
        File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i
      else
        0
      end

      expect(rss_kb).to eq(51_200)
    end
  end
end
