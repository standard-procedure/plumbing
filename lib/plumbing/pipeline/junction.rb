# frozen_string_literal: true

module Plumbing
  class Pipeline
    # Fan-in: merges several sources into one, re-emitting every event from each.
    class Junction < Plumbing::Pipeline
      def initialize(*sources)
        super()
        sources.each { |source| _add(source:) }
      end

      async :add do
        param :source, Plumbing.Observable

        calls do |source:|
          chain(source) { true }
        end
      end
    end
  end
end
