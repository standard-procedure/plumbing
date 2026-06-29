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

      async :advance do
        returns { run_loop }
      end

      attr_reader :current_state

      def in?(name) = @current_state == name.to_sym

      def completed? = @status == :completed

      def failed? = @status == :failed

      attr_reader :exception

      private

      def setup_attributes(attrs)
        @attributes = self.class.attributes_schema.new(**attrs)
      end

      def start(attrs)
        setup_attributes(attrs)
        @current_state = self.class.start_state
        enter_running
        advance
      end

      def start_at(state, attrs)
        setup_attributes(attrs)
        @current_state = state
        enter_running
        advance
      end

      def enter_running
        @status = :running
        emit Started.new(operation_id: object_id, state: @current_state, attributes: attributes)
      end

      def run_loop
        loop do
          state = self.class.states.fetch(@current_state)
          case state.kind
          when :result
            @status = :completed
            emit Completed.new(operation_id: object_id, state: state.name, attributes: attributes)
          when :action
            instance_exec(&state.action) if state.action
            transition = state.transitions.first
            raise NoTransition, "action :#{state.name} needs a `.then`" if transition.nil?
            move_to(transition)
          when :decision
            transition = state.transitions.find { |t| t.matches?(self) }
            raise NoDecision, "no condition matched in :#{state.name}" if transition.nil?
            move_to(transition)
          end
          break unless @status == :running
        end
      rescue => ex
        @status = :failed
        @exception = ex
        emit Failed.new(operation_id: object_id, state: @current_state, exception: ex, attributes: attributes)
      end

      def move_to(transition)
        from = @current_state
        @current_state = transition.target
        emit Transitioned.new(operation_id: object_id, from: from, to: @current_state, via: transition.label, attributes: attributes)
      end

      def emit(event) = @pipeline&.push(event: event)
    end
  end
end
