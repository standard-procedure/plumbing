# frozen_string_literal: true

require_relative "base"

module Plumbing
  class Pipeline
    # Emits every event EXCEPT those whose type name matches one of the filters
    # (trailing `*` is a prefix wildcard, e.g. "Error*").
    class Except < Base
      def initialize(source:, filters: [])
        super()
        list = Array(filters)
        chain(source) { |event| !wildcard_match?(list, event.class.name) }
      end
    end
  end
end
