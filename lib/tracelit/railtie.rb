# frozen_string_literal: true

module Tracelit
  # Railtie hooks Tracelit into the Rails boot sequence automatically.
  # No explicit initializer call needed — adding the gem to the Gemfile
  # is sufficient for Rails apps.
  class Railtie < ::Rails::Railtie
    # Run after the app is initialized so config/initializers/ have
    # already been evaluated and Tracelit.configure { } blocks applied.
    initializer "tracelit.configure", after: :load_config_initializers do
      Tracelit::Instrumentation.setup(Tracelit.config)
    end
  end
end
