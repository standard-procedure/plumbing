# frozen_string_literal: true

module Plumbing
  class Pipeline
    # Emits only the events whose type name matches one of the filters
    # (trailing `*` is a prefix wildcard, e.g. "Error*").
    class Only < Plumbing::Pipeline
      def initialize(source:, filters: [])
        super()
        list = Array(filters)
        chain(source) { |event| wildcard_match?(list, event.class.name) }
      end
    end
  end
end
