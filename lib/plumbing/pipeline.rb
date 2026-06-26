# frozen_string_literal: true

require_relative "event"

module Plumbing
  # Namespace + event registry for the composable event pipeline. Concrete
  # pipelines are Pipeline::Source / Only / Except / Filter / Junction; they all
  # emit immutable Plumbing::Event values to registered observers.
  class Pipeline
    @event_types = {}

    class << self
      # Register an event class so #notify can build it from its type name
      # (and so deserialisation has a known, allow-listed set of types).
      def register(klass)
        raise ArgumentError, "#{klass} is not a Plumbing::Event" unless klass.is_a?(Class) && klass < Plumbing::Event
        @event_types[klass.name] = klass
        klass
      end

      def event_type(name) = @event_types.fetch(name)

      def registered_event_types = @event_types.keys
    end
  end
end

require_relative "pipeline/base"
require_relative "pipeline/source"
require_relative "pipeline/only"
require_relative "pipeline/except"
require_relative "pipeline/filter"
require_relative "pipeline/junction"
