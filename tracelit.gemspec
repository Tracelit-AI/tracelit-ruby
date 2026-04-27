# frozen_string_literal: true

require_relative "lib/tracelit/version"

Gem::Specification.new do |spec|
  spec.name          = "tracelit"
  spec.version       = Tracelit::VERSION
  spec.authors       = ["Tracelit"]
  spec.email         = ["hey@tracelit.io"]
  spec.summary       = "Official Ruby SDK for Tracelit backend observability"
  spec.description   = "Drop-in OpenTelemetry instrumentation for Rails, Sinatra, " \
                       "and Rack apps. Sends traces, metrics, and logs to the " \
                       "Tracelit ingest API via OTLP/HTTP."
  spec.homepage      = "https://tracelit.io"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "tracelit.gemspec",
    "README.md"
  ]

  spec.require_paths = ["lib"]

  # Core OTel runtime dependencies
  spec.add_dependency "opentelemetry-sdk",                 "~> 1.4"
  spec.add_dependency "opentelemetry-exporter-otlp",       "~> 0.26"
  spec.add_dependency "opentelemetry-instrumentation-all", "~> 0.62"
  spec.add_dependency "opentelemetry-logs-sdk",            "~> 0.5"
  spec.add_dependency "opentelemetry-exporter-otlp-logs",  "~> 0.4"
  spec.add_dependency "opentelemetry-metrics-sdk",            "~> 0.13"
  spec.add_dependency "opentelemetry-exporter-otlp-metrics",  "~> 0.8"
end
