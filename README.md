# Tracelit Ruby SDK

Official Ruby SDK for [Tracelit](https://tracelit.io) — drop-in OpenTelemetry instrumentation for Rails, Sinatra, and Rack apps. Sends traces, metrics, and logs to the Tracelit ingest API via OTLP/HTTP.

**Requirements:** Ruby >= 3.0

---

## Set up with AI

Want an AI assistant (Cursor, Claude, ChatGPT, etc.) to integrate Tracelit into your app automatically? Copy the contents of [`llm_prompt.txt`](./llm_prompt.txt) and paste it as your prompt. It covers gem installation, initializer setup, manual spans, custom metrics, and test guard — everything the AI needs in one shot.

---

## Installation

Add to your `Gemfile` and run `bundle install`:

```ruby
gem "tracelit"
```

---

## Setup

### Rails

Create `config/initializers/tracelit.rb`:

```ruby
Tracelit.configure do |config|
  config.api_key      = ENV["TRACELIT_API_KEY"]   # required
  config.service_name = "payments-api"             # required
  config.environment  = ENV["RAILS_ENV"]
  config.sample_rate  = 1.0
end
```

That is all. The Railtie picks up the configuration automatically and calls `Tracelit.start!` at boot — no further changes needed.

### Sinatra / Rack

```ruby
require "tracelit"

Tracelit.configure do |config|
  config.api_key      = ENV["TRACELIT_API_KEY"]
  config.service_name = "my-sinatra-app"
  config.environment  = ENV["RACK_ENV"]
end

Tracelit.start!   # must be called explicitly outside Rails
```

---

## Configuration reference

All options can be set in the `configure` block or via environment variables.

| Option | Env variable | Default | Description |
|---|---|---|---|
| `api_key` | `TRACELIT_API_KEY` | `nil` | **Required.** Your Tracelit ingest API key. |
| `service_name` | `TRACELIT_SERVICE_NAME` | Rails app name | **Required.** Name of this service as it appears in Tracelit. Falls back to the Rails application module name when inside Rails, or `"unknown-service"` otherwise. |
| `environment` | `TRACELIT_ENVIRONMENT` | `"production"` | Deployment environment tag — e.g. `production`, `staging`, `development`. |
| `endpoint` | `TRACELIT_ENDPOINT` | `https://ingest.tracelit.app` | Base URL of the Tracelit ingest API. Override only when self-hosting. |
| `sample_rate` | `TRACELIT_SAMPLE_RATE` | `1.0` | Head-based trace sampling ratio between `0.0` and `1.0`. `1.0` keeps every trace; `0.1` keeps 10%. **Errors are always exported regardless of this setting.** |
| `enabled` | `TRACELIT_ENABLED` | `true` | Set to `false` (or `TRACELIT_ENABLED=false`) to disable all telemetry without removing the gem — useful in test environments. |
| `resource_attributes` | — | `{}` | Extra key/value pairs appended to every span, metric, and log record as resource attributes. |

### Adding custom resource attributes

```ruby
Tracelit.configure do |config|
  config.api_key      = ENV["TRACELIT_API_KEY"]
  config.service_name = "orders-api"
  config.resource_attributes = {
    "deployment.region" => "us-east-1",
    "team"              => "platform",
  }
end
```

---

## Manual trace instrumentation

Use `Tracelit.tracer` to create custom spans around any block of work:

```ruby
Tracelit.tracer.in_span("process_payment") do |span|
  span.set_attribute("payment.id",       payment.id.to_s)
  span.set_attribute("payment.amount",   amount)
  span.set_attribute("payment.currency", currency)

  result = process(payment)

  span.set_attribute("payment.status", result.status)
  result
end
```

The tracer is an `OpenTelemetry::Trace::Tracer` and supports the full [OpenTelemetry Ruby API](https://opentelemetry.io/docs/languages/ruby/api/).

---

## Manual metrics instrumentation

Access the metrics interface via `Tracelit.metrics` (an alias for `Tracelit::Metrics`):

### Counter

Counts discrete events. Use for request counts, job completions, errors, etc.

```ruby
counter = Tracelit.metrics.counter(
  "orders.placed",
  description: "Total orders placed",
  unit: "{orders}"
)

counter.add(1, attributes: { "currency" => "USD", "channel" => "web" })
```

### Histogram

Records distributions of values. Use for durations, payload sizes, queue depths, etc.

```ruby
histogram = Tracelit.metrics.histogram(
  "external.api.duration",
  description: "External API call duration",
  unit: "ms"
)

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
call_external_api
elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

histogram.record(elapsed_ms, attributes: { "service" => "stripe" })
```

### Gauge

Records a point-in-time value. Use for pool sizes, queue lengths, cache hit rates, etc.

```ruby
gauge = Tracelit.metrics.gauge(
  "job_queue.depth",
  description: "Number of pending background jobs",
  unit: "{jobs}"
)

gauge.record(JobQueue.pending_count, attributes: { "queue" => "default" })
```

---

## Automatic instrumentation

The SDK enables every instrumentation gem bundled in `opentelemetry-instrumentation-all`, including:

| Library | What is captured |
|---|---|
| Rails / Action Pack | HTTP request traces, controller and action attributes |
| Active Record | SQL query traces with sanitised statement text |
| Action View | Template render times |
| Rack | Low-level HTTP middleware spans |
| Net::HTTP | Outbound HTTP call traces |
| Faraday | Outbound HTTP call traces |
| Redis | Cache command traces |
| Sidekiq | Job enqueue and execute traces |
| Bunny | AMQP publish/subscribe traces |
| gRPC | Client and server RPC traces |

Additional libraries (Mongo, pg, mysql2, Kafka, etc.) are also instrumented when their gems are present.

---

## Automatic metrics collection

Once `Tracelit.start!` has been called, the following metrics are collected with no additional configuration:

### HTTP server metrics (Rails)

Emitted per request via `ActiveSupport::Notifications`:

| Metric | Type | Description |
|---|---|---|
| `http.server.request.count` | Counter | Total HTTP requests processed |
| `http.server.request.duration` | Histogram | Request duration in milliseconds |
| `http.server.error.count` | Counter | Total 5xx responses |
| `db.query.duration` | Histogram | ActiveRecord time per request in milliseconds |

Attributes on all HTTP metrics: `http.method`, `http.route`, `http.status_code`, `controller`, `action`.

### Sidekiq job metrics

Emitted per job execution via server middleware:

| Metric | Type | Description |
|---|---|---|
| `sidekiq.job.count` | Counter | Total jobs processed |
| `sidekiq.job.duration` | Histogram | Job execution duration in milliseconds |
| `sidekiq.job.error.count` | Counter | Total jobs that raised an error |

Attributes: `sidekiq.job.class`, `sidekiq.queue`, `sidekiq.status` (`success` or `error`).

### Database connection pool metrics (ActiveRecord)

Polled every 30 seconds on a background thread:

| Metric | Type | Description |
|---|---|---|
| `db.connection_pool.size` | Gauge | Maximum connections in the pool |
| `db.connection_pool.busy` | Gauge | Connections currently checked out |
| `db.connection_pool.idle` | Gauge | Connections available for checkout |
| `db.connection_pool.waiting` | Gauge | Threads waiting for a connection |

### Process memory

Polled every 60 seconds:

| Metric | Type | Description |
|---|---|---|
| `process.memory.rss` | Gauge | Process RSS memory in megabytes |

---

## Log forwarding (Rails)

When Rails is present, `Tracelit.start!` installs a broadcast target on `Rails.logger`. Every `Rails.logger` call is forwarded to the OTel LoggerProvider and exported to the Tracelit logs table via OTLP. The original logger output is preserved — nothing changes for your existing log pipeline.

Log records are automatically correlated with the active trace via `trace_id` and `span_id`.

---

## Sampling and error guarantee

Set `config.sample_rate` below `1.0` to reduce trace volume in high-traffic environments:

```ruby
config.sample_rate = 0.1   # keep 10% of traces
```

**Error spans are always exported**, even when the parent trace is outside the sample ratio. The SDK uses a custom `ErrorAlwaysOnSampler` + `ErrorSpanProcessor` pair to guarantee this — no configuration required.

---

## Disabling in tests

```ruby
# config/initializers/tracelit.rb
Tracelit.configure do |config|
  config.api_key      = ENV["TRACELIT_API_KEY"]
  config.service_name = "my-app"
  config.enabled      = ENV["TRACELIT_ENABLED"] != "false"
end
```

Then in your test environment:

```bash
TRACELIT_ENABLED=false bundle exec rspec
```

Or set it permanently in `config/environments/test.rb` / `.env.test`:

```
TRACELIT_ENABLED=false
```

---

## Running the SDK's own tests

```bash
bundle install
bundle exec rspec
```
