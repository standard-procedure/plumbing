# frozen_string_literal: true

module Plumbing
  class Pipeline
    # Emits only the events whose type name matches one of the Regexp filters.
    # The power-user form (Only/Except cover the common wildcard cases).
    class Filter < Plumbing::Pipeline
      def initialize(source:, filters: [])
        super()
        list = Array(filters)
        chain(source) { |event| list.any? { |regexp| regexp.match?(event.class.name) } }
      end
    end
  end
end
