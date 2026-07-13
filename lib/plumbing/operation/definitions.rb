# frozen_string_literal: true

module Plumbing
  class Operation
    module Definitions
      # define an initialiser that is called before startup
      def starts_with(&initialiser)
        @initialiser = initialiser
      end

      # define an action state
      def action(name, &implementation)
        states << Action.new(name:, implementation:)
      end

      # which is the next state after an action
      def go_to state
        Literal.check state, Symbol
        next_states << state
      end

      # define a decision state with conditional transitions
      def decision(name, &conditions)
        states << Decision.build(name:, &conditions)
        next_states << nil
      end

      # define a waiting state with conditional transitions
      def wait_until(name, delay: nil, timeout: nil, &conditions)
        Literal.check name, Symbol
        Literal.check delay, _Integer?
        Literal.check timeout, _Integer?

        states << Wait.build(name:, delay: delay || default_delay, timeout: timeout || default_timeout, &conditions)
        next_states << nil
      end

      # define an interaction from a user or external system
      def interaction(name, &configuration)
        Literal.check name, Symbol
        interactions << name
        async name, &configuration
        after_message do |method, params, result|
          advance if method == name
        end
      end

      # define an end state
      def result name
        states << Result.new(name: name)
        next_states << nil
      end

      def initial_state = states.first

      def states
        @states ||= []
      end

      def next_states
        @next_states ||= []
      end

      def delay seconds
        @default_delay = seconds
      end

      def default_delay
        @default_delay ||= 10
      end

      def timeout seconds
        @default_timeout = seconds
      end

      def default_timeout
        @default_timeout ||= 86_400
      end

      def interactions
        @interactions ||= []
      end

      def initialiser
        @initialiser ||= -> {}
      end

      class State < Literal::Struct
        prop :name, Symbol, reader: :public, writer: false
      end

      class Action < State
        prop :implementation, _Callable

        def call operation
          operation.instance_exec(&@implementation)
          operation.move_to_next_state
        end
      end

      class Condition < Literal::Data
        prop :state, Symbol
        prop :condition, _Callable
      end

      class Decision < State
        prop :conditions, _Array(Condition)

        def call operation
          condition = _find_matching_condition_for operation
          raise Plumbing::Operation::NoDecision if condition.nil?
          operation.move_to condition.state
        end

        private def _find_matching_condition_for operation
          @conditions.find { |c| !!operation.instance_exec(&c.condition) }
        end

        def self.build(name:, &config) = Builder.new(name:).call(&config)

        class Builder < Literal::Object
          prop :name, Symbol
          prop :conditions, _Array(Condition), default: -> { [] }

          def go_to state, **params
            @conditions << Condition.new(state: state, condition: params[:if])
          end

          def call(&config)
            instance_exec(&config)
            Decision.new(name: @name, conditions: @conditions)
          end
        end
      end

      class Wait < Decision
        prop :delay, Integer
        prop :timeout, Integer

        def call operation
          condition = _find_matching_condition_for operation
          condition.nil? ? operation.wait : operation.move_to(condition.state)
        end

        def self.build(name:, delay:, timeout:, &config) = Builder.new(name:, delay:, timeout:).call(&config)

        class Builder < Literal::Object
          prop :name, Symbol
          prop :delay, Integer
          prop :timeout, Integer
          prop :conditions, _Array(Condition), default: -> { [] }

          def go_to state, **params
            @conditions << Condition.new(state: state, condition: params[:if])
          end

          def call(&config)
            instance_exec(&config)
            Wait.new(name: @name, delay: @delay, timeout: @timeout, conditions: @conditions)
          end
        end
      end

      class Result < State
        def call operation
          operation.completed
        end
      end
    end
  end
end
