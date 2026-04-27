# frozen_string_literal: true

require_relative "../../lib/tracelit/error_span_processor"

RSpec.describe Tracelit::ErrorSpanProcessor do
  let(:exporter) { instance_double("Exporter", export: nil, force_flush: nil) }
  subject(:processor) { described_class.new(exporter) }

  describe "#on_start" do
    it "returns without doing anything" do
      expect { processor.on_start(double("span"), double("context")) }.not_to raise_error
    end
  end

  describe "#on_finish" do
    let(:status)      { double("Status") }
    let(:trace_flags) { double("TraceFlags") }
    let(:context)     { double("SpanContext", trace_flags: trace_flags) }
    let(:span_data)   { double("SpanData") }
    let(:span) do
      double("Span", status: status, context: context, to_span_data: span_data)
    end

    context "when the span status is OK (not an error)" do
      before { allow(status).to receive(:ok?).and_return(true) }

      it "does not call the exporter" do
        processor.on_finish(span)
        expect(exporter).not_to have_received(:export)
      end
    end

    context "when the span has an error but was already sampled" do
      before do
        allow(status).to receive(:ok?).and_return(false)
        allow(trace_flags).to receive(:sampled?).and_return(true)
      end

      it "does not call the exporter (BatchSpanProcessor handles sampled spans)" do
        processor.on_finish(span)
        expect(exporter).not_to have_received(:export)
      end
    end

    context "when the span has an error and was not sampled" do
      before do
        allow(status).to receive(:ok?).and_return(false)
        allow(trace_flags).to receive(:sampled?).and_return(false)
      end

      it "force-exports the span data to the exporter" do
        processor.on_finish(span)
        expect(exporter).to have_received(:export).with([span_data])
      end
    end

    context "when the exporter raises an error" do
      before do
        allow(status).to receive(:ok?).and_return(false)
        allow(trace_flags).to receive(:sampled?).and_return(false)
        allow(exporter).to receive(:export).and_raise(RuntimeError, "network timeout")
      end

      it "swallows the exception and does not propagate it to the application" do
        expect { processor.on_finish(span) }.not_to raise_error
      end
    end
  end

  describe "#force_flush" do
    it "delegates to the exporter with the given timeout" do
      processor.force_flush(timeout: 5)
      expect(exporter).to have_received(:force_flush).with(timeout: 5)
    end
  end

  describe "#shutdown" do
    it "does not touch the shared exporter (lifecycle owned by BatchSpanProcessor)" do
      processor.shutdown(timeout: 5)
      expect(exporter).not_to have_received(:export)
    end
  end
end
