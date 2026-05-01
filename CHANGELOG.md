# Changelog

All notable changes to the Tracelit Ruby SDK will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.4] — 2026-05-01

### Fixed

- **ProxyTracerProvider cascade** — when `OpenTelemetry::SDK.configure` fails internally (e.g. a bad resource attribute or an instrumentation gem error caught by the error handler), the global tracer provider remains the pre-boot `ProxyTracerProvider` which does not respond to `.resource`. `setup_logs` and `Metrics.setup` now guard this call with `respond_to?(:resource)` and fall back to an empty resource, preventing the `undefined method 'resource' for ProxyTracerProvider` error.
- **Post-configure provider check** — `Instrumentation.setup` now checks immediately after `OpenTelemetry::SDK.configure` whether the tracer provider is a real SDK provider. If the SDK did not fully initialize, a clear single-line warning is logged and the logs/metrics pipelines are skipped cleanly rather than failing with cryptic `NoMethodError`s.
- **`resource_attributes` type safety** — `Configuration#sanitized_resource_attributes` filters out any value that is not a `String`, `Integer`, `Float`, `true`, or `false` and coerces all keys to strings. This prevents `OpenTelemetry::SDK::ConfigurationError` when users accidentally pass symbol values or `nil` as resource attribute values.
- **`resolved_commit_sha` missing** — `config.resolved_commit_sha` was referenced in `Instrumentation` but not defined on `Configuration`, causing a `NoMethodError` inside the SDK configure block (caught by the error handler, but enough to leave the SDK in a bad state). The method is now defined and reads from `TRACELIT_COMMIT_SHA`, `HEROKU_SLUG_COMMIT`, `SOURCE_VERSION`, `RENDER_GIT_COMMIT`, or `GITHUB_SHA` in that order.

---

## [0.1.3] — 2026-05-01

### Fixed

- **Never crash the host app** — `Configuration#validate!` is now a no-op. A new `valid?` method returns an array of error strings; `Instrumentation.setup` logs a `[Tracelit] disabled` warning and returns early instead of raising `ArgumentError`.
- **validate! logic bug** — validation now checks `resolved_service_name` (which infers the Rails app name) rather than the raw `service_name` attribute. Rails users who rely on automatic name inference no longer get a false "service_name is required" error.
- **Custom OTel error handler** — installed at the start of `setup` so internal OTel errors (failed exports, instrumentation hiccups, shutdown crashes) are emitted as single-line `[Tracelit]` warnings rather than raw stack traces.
- **Thread-safe setup** — `Instrumentation.setup` is now wrapped in `SETUP_MUTEX` to prevent race conditions when multiple Puma threads boot concurrently.
- **Puma / Unicorn fork safety** — a `Process._fork` hook (Ruby 3.1+) restarts background polling threads in each forked worker process so metrics are collected in every worker, not just the master.
- **Double-subscription guard** — `install_rails_subscriber` and `install_sidekiq_middleware` are now idempotent; calling `reset!` + `setup` (common in tests and Rails reload scenarios) no longer registers duplicate subscribers or middleware.
- **`http.route` cardinality explosion** — the `http.route` metric attribute now uses `Controller#action` (stable, low-cardinality) instead of `payload[:path]` (full URL with resource IDs), preventing unbounded metric series growth.
- **ENV mutation** — `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` is now set with `||=` at module load time instead of inside `setup`, preserving any value the user has already configured.
- **Graceful shutdown** — an `at_exit` hook now flushes and shuts down both the tracer provider and meter provider on process exit, preventing loss of the last metrics/trace batch during deploys.
- **RailsLoggerBridge re-entrancy** — a thread-local guard in `OTelLogger#add` prevents the feedback loop where OTel internal warnings (routed through `OpenTelemetry.logger`) would re-trigger a log emit via the bridge.
- **Rails version compatibility** — connection pool access now works on Rails 6.0–8.x: uses `connection_handler.retrieve_connection_pool` with a `connection_pool` fallback, and checks `respond_to?(:pool_config)` before accessing the `db_config.adapter` attribute.
- **Memory poller reliability** — on Linux, `/proc/self/status` is now used to read RSS instead of spawning a `ps` subprocess. This works in minimal Docker containers (distroless, alpine without procps) and is zero-overhead. `ps` is kept as a macOS/BSD fallback.

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
