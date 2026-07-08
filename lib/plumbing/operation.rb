# frozen_string_literal: true

require_relative "actor"
require_relative "event"
require_relative "pipeline"
require_relative "observable"

module Plumbing
  # Base class for operations. Subclass it and declare attributes + states
  # with the DSL. An Operation is a Plumbing::Actor.
  class Operation < Literal::Struct
    require_relative "operation/errors"
    require_relative "operation/transition"
    require_relative "operation/wait_options"
    require_relative "operation/state"
    require_relative "operation/events"
    require_relative "operation/dsl"
    require_relative "operation/mermaid"
    include Plumbing::Actor
    include Plumbing::Observable
    extend DSL
    extend Mermaid

    prop :current_state, _Symbol?, default: nil, writer: false
    prop :status, Symbol, default: :pending, writer: false
    prop :attributes, Hash, default: -> { {} }, reader: false, writer: false
    prop :exception, _Nilable(Exception), default: nil, writer: false
    prop :timeout_id, _Nilable(Actor::Deferral), default: nil, writer: false
    prop :poll_id, _Nilable(Actor::Deferral), default: nil, writer: false
    prop :waiting_state, _String?, default: nil, writer: false
    prop :wait_generation, _Integer, default: 0, writer: false
    prop :wait_started_at, _Float?, default: nil, writer: false
    prop :restore_wait_elapsed, _Float?, default: nil, writer: false

    def attributes = @attributes.to_h

    async :advance do
      param :poll_token, _Nilable(Integer), default: nil
      returns { |poll_token:| run_loop unless stale_poll?(poll_token) }
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
      worker.call
      advance
    end

    def start_at(state, attrs)
      setup_attributes(attrs)
      @current_state = state
      enter_running
      worker.call
      advance
    end

    def resume(state, attrs, wait_elapsed)
      setup_attributes(attrs)
      @current_state = state
      @status = :running
      @restored_wait_elapsed = wait_elapsed
      worker.call
      advance
    end

    def enter_running
      @status = :running
      push Started.new(operation_id: object_id, state: @current_state, attributes: attributes)
    end

    def run_loop
      loop do
        state = self.class.states.fetch(@current_state)
        case state.kind
        when :result
          @status = :completed
          push Completed.new(operation_id: object_id, state: state.name, attributes: attributes)
        when :action
          instance_exec(&state.action) if state.action
          transition = state.transitions.first
          raise NoTransition, "action :#{state.name} needs a `.then`" if transition.nil?
          move_to(transition)
        when :decision
          transition = state.transitions.find { |t| t.matches?(self) }
          raise NoDecision, "no condition matched in :#{state.name}" if transition.nil?
          move_to(transition)
        when :wait
          enter_wait(state) unless @waiting_state == state.name
          transition = state.transitions.find { |t| t.matches?(self) }
          if transition
            leave_wait
            move_to(transition)
          elsif timed_out?(state)
            leave_wait
            raise Timeout, "wait :#{state.name} exceeded #{state.wait_options.timeout}s"
          else
            reschedule_poll(state)
            break
          end
        end
        break unless @status == :running
      end
    rescue => ex
      leave_wait
      @status = :failed
      @exception = ex
      push Failed.new(operation_id: object_id, state: @current_state, exception: ex, attributes: attributes)
    end

    def move_to(transition)
      from = @current_state
      @current_state = transition.target
      push Transitioned.new(operation_id: object_id, from: from, to: @current_state, via: transition.label, attributes: attributes)
    end

    def stale_poll?(token) = !token.nil? && token != @wait_generation

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def enter_wait(state)
      @waiting_state = state.name
      @wait_generation += 1
      @wait_started_at = monotonic - (@restored_wait_elapsed || 0.0)
      @restored_wait_elapsed = nil
      @timeout_id = after(state.wait_options.timeout, call: :advance, poll_token: @wait_generation)
      push Waiting.new(operation_id: object_id, state: state.name, attributes: attributes)
    end

    def reschedule_poll(state)
      cancel_deferred(@poll_id) if @poll_id
      @poll_id = after(state.wait_options.delay, call: :advance, poll_token: @wait_generation)
    end

    def timed_out?(state)
      return false if @wait_started_at.nil?
      (monotonic - @wait_started_at) >= state.wait_options.timeout
    end

    def leave_wait
      cancel_deferred(@poll_id) if @poll_id
      cancel_deferred(@timeout_id) if @timeout_id
      @wait_generation += 1
      @poll_id = @timeout_id = @waiting_state = @wait_started_at = nil
    end
  end
end
