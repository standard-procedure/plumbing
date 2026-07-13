# frozen_string_literal: true
module Plumbing
  # Base class for pipeline events: an immutable, value-comparable Literal::Data.
  # Subclasses declare their payload with `prop`. Because Literal::Data is frozen
  # and hashes on its properties, equal events are interchangeable and can be
  # used as Set keys (which is how the pipeline debounces duplicates).
  class Event < Literal::Data
    prop :event_type, String, default: -> { self.class.name }
    prop :source, Plumbing.Observable

    require_relative "event/types"

    def self.types
      @types ||= Event::Types.new
    end
  end
end
