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

      def states = @states ||= {}

      def starts_with(name) = @start_state = name.to_sym

      def start_state = @start_state

      def action(name, &body)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :action, action: body)
        ActionBuilder.new(self, name.to_sym)
      end

      def decision(name, &block)
        builder = DecisionBuilder.new
        builder.instance_eval(&block)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :decision, transitions: builder.transitions.freeze)
        name.to_sym
      end

      def result(name)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :result)
        name.to_sym
      end

      def call(pipeline: nil, **attrs)
        new(pipeline: pipeline).tap { |op| op.__send__(:start, attrs) }
      end

      def test(state, pipeline: nil, **attrs)
        new(pipeline: pipeline).tap { |op| op.__send__(:start_at, state.to_sym, attrs) }
      end
    end

    # Returned by `action` so `.then` can set its single transition.
    class ActionBuilder
      def initialize(klass, name)
        @klass = klass
        @name = name
      end

      def then(target)
        state = @klass.states.fetch(@name)
        @klass.states[@name] = State.new(**state.to_h.merge(transitions: [Transition.new(target: target.to_sym, guard: nil, label: nil)].freeze))
        @name
      end
    end

    # Collects `go_to` calls inside a `decision` block.
    class DecisionBuilder
      attr_reader :transitions

      def initialize = @transitions = []

      def go_to(target, label = nil, **opts)
        @transitions << Transition.new(target: target.to_sym, guard: opts[:if], label: label)
      end
    end
  end
end
