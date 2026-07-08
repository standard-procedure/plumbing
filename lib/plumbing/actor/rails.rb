# frozen_string_literal: true

require_relative "threaded"

module Plumbing
  module Actor
    # Rails-safe variant of the threaded worker: wraps each delivery in the
    # Rails executor, so ActiveRecord connections and code reloading are managed
    # correctly per message. Requires a booted Rails app at runtime.
    class Rails < Threaded
      private def run_loop
        while (message = @queue.pop)
          ::Rails.application.executor.wrap { message.deliver }
        end
      end
    end
  end
end

# Opt-in worker: requiring this file registers it. Select with
# `Plumbing::Actor.uses :rails` (the app must be running inside Rails).
Plumbing::Actor.register(:rails) { |actor| Plumbing::Actor::Rails.new(actor: actor) }
