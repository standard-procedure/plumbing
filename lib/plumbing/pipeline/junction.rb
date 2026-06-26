# frozen_string_literal: true

require_relative "base"

module Plumbing
  class Pipeline
    # Fan-in: merges several sources into one, re-emitting every event from each.
    class Junction < Base
      def initialize(*sources)
        super()
        sources.each { |source| chain(source) { true } }
      end
    end
  end
end
