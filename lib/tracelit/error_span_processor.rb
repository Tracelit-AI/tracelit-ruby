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
  #
  # Important: this processor must never block application threads. Exporting an
  # unsampled error span synchronously in on_finish can block request / console
  # threads when the ingest endpoint is slow or retrying. We enqueue span data
  # into a bounded in-memory queue and export on a background worker thread.
  class ErrorSpanProcessor
    QUEUE_CAPACITY = 512
    SHUTDOWN_SENTINEL = Object.new

    def initialize(exporter)
      @exporter = exporter
      @queue = SizedQueue.new(QUEUE_CAPACITY)
      @shutdown = false
      @worker = Thread.new do
        Thread.current[:tracelit_error_export_worker] = true
        worker_loop
      end
      @worker.abort_on_exception = false
    end

    def on_start(_span, _parent_context)
      # nothing to do at start
    end

    def on_finish(span)
      # Skip spans that are not in error — only intervene for errors
      return if span.status.ok?

      # Skip spans that were fully sampled — BatchSpanProcessor handles those.
      # This prevents double-export of error spans on traces that were sampled.
      return if span.context.trace_flags.sampled?

      # Queue for background export; never block the caller.
      enqueue(span.to_span_data)
    rescue StandardError
      # Never let processor errors propagate to the application
    end

    def force_flush(timeout: nil)
      wait_for_queue_drain(timeout)
      @exporter.force_flush(timeout: timeout)
    end

    def shutdown(timeout: nil)
      return if @shutdown
      @shutdown = true
      enqueue_shutdown_signal
      @worker&.join(timeout || 1)
      # Do not shut down the shared exporter here —
      # the BatchSpanProcessor owns its lifecycle
    end

    private

    def worker_loop
      loop do
        item = @queue.pop
        break if item.equal?(SHUTDOWN_SENTINEL)

        begin
          @exporter.export([item])
        rescue StandardError
          # Never let exporter failures crash the app worker thread
        end
      end
    rescue StandardError
      # Last-ditch guard: processor background failures must stay isolated.
    end

    def enqueue(span_data)
      @queue.push(span_data, true)
    rescue ThreadError
      # Queue full — drop to protect application latency.
    end

    def enqueue_shutdown_signal
      @queue.push(SHUTDOWN_SENTINEL, true)
    rescue ThreadError
      # Queue is full: drop one oldest item and retry so shutdown can proceed.
      begin
        @queue.pop(true)
      rescue ThreadError
        # no-op
      end
      begin
        @queue.push(SHUTDOWN_SENTINEL, true)
      rescue ThreadError
        # no-op — join timeout is a final guard
      end
    end

    def wait_for_queue_drain(timeout)
      deadline = timeout ? Time.now + timeout : nil
      until @queue.empty?
        break if deadline && Time.now >= deadline
        sleep(0.01)
      end
    end
  end
end
