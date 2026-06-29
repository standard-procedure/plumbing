# frozen_string_literal: true

require_relative "state"

module Plumbing
  module Operations
    # Class-level authoring DSL, extended onto Task. This file carries the
    # attribute mechanism; state builders are added in a later task.
    module DSL
      # The per-class Literal::Struct that holds attribute values. Mutable, so
      # actions can assign (self.x = ...).
      def attributes_schema
        @attributes_schema ||= Class.new(Literal::Struct)
      end

      # Declare a typed attribute. Adds a prop to the schema and defines
      # delegating reader/writer methods on instances.
      def attribute(name, type, **opts)
        attributes_schema.prop(name, type, **opts)
        define_method(name) { @attributes.public_send(name) }
        define_method(:"#{name}=") { |value| @attributes.public_send(:"#{name}=", value) }
        name.to_sym
      end
    end
  end
end
