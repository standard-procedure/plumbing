# frozen_string_literal: true

require_relative "dsl"

module Plumbing
  module Operations
    # Base class for operations. Subclass it and declare attributes + states
    # with the DSL. A Task is a Plumbing::Actor.
    class Task
      include Plumbing::Actor
      extend Literal::Types
      extend DSL

      def initialize(pipeline: nil)
        super()
        @pipeline = pipeline
        @status = :pending
      end

      def attributes = @attributes.to_h

      private

      def setup_attributes(attrs)
        @attributes = self.class.attributes_schema.new(**attrs)
      end
    end
  end
end
