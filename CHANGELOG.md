# Changelog

All notable changes to the Tracelit Ruby SDK will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] — 2026-04-27

### Added

- **Traces** — OpenTelemetry SDK integration with OTLP/HTTP export to the Tracelit ingest API.
- **Auto-instrumentation** — Rails, Rack, ActiveRecord, Action View, Net::HTTP, Faraday, Redis, Sidekiq, and 30+ more libraries via `opentelemetry-instrumentation-all`.
- **Metrics** — OTel Metrics SDK with OTLP/HTTP export (delta temporality).
  - `http.server.request.count`, `http.server.request.duration`, `http.server.error.count`, `db.query.duration` via Rails `ActiveSupport::Notifications`.
  - `sidekiq.job.count`, `sidekiq.job.duration`, `sidekiq.job.error.count` via Sidekiq server middleware.
  - `db.connection_pool.size/busy/idle/waiting` polled every 30 s from ActiveRecord.
  - `process.memory.rss` polled every 60 s via `ps`.
- **Logs** — OTel Logs SDK with OTLP/HTTP export. Rails.logger broadcast target forwards every log line to Tracelit, correlated to the active trace via `trace_id` and `span_id`.
- **Error guarantee** — `ErrorAlwaysOnSampler` + `ErrorSpanProcessor` ensure error spans are always exported regardless of the configured `sample_rate`.
- **Railtie** — automatic setup at Rails boot; no explicit `Tracelit.start!` call needed.
- **Manual instrumentation API** — `Tracelit.tracer` for custom spans; `Tracelit.metrics.counter/histogram/gauge` for custom metrics.
- **Configuration** — all options settable via `Tracelit.configure` block or environment variables (`TRACELIT_API_KEY`, `TRACELIT_SERVICE_NAME`, `TRACELIT_ENVIRONMENT`, `TRACELIT_ENDPOINT`, `TRACELIT_SAMPLE_RATE`, `TRACELIT_ENABLED`).
