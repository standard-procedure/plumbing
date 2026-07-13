# frozen_string_literal: true

require "async"
require_relative "actor"
require_relative "event"
require_relative "pipeline"

module Plumbing
  # Base class for operations. Subclass it and declare attributes + states
  # with the DSL. An Operation is a Plumbing::Actor.
  class Operation < Literal::Struct
    require_relative "operation/errors"
    require_relative "operation/transition"
    require_relative "operation/wait_options"
    require_relative "operation/events"
    require_relative "operation/definitions"
    require_relative "operation/mermaid"
    include Plumbing::Actor
    include Plumbing::Actor::Observable

    extend Definitions
    extend Mermaid

    STATUSES = [:pending, :running, :waiting, :completed, :failed].freeze

    prop :current, _Integer, default: 0, writer: false
    prop :status, Plumbing.OneOf(:pending, :running, :waiting, :completed, :failed), default: :pending, writer: false
    prop :exception, _Nilable(StandardError), default: nil, reader: :public, writer: false

    async :advance do
      calls do
        run_loop
      end
    end

    def current_state = self.class.states[@current]
    def next_state = self.class.next_states[@current]

    def in?(name) = current_state.name == name.to_sym

    STATUSES.each do |status|
      define_method(:"#{status}?") { @status == status }
    end

    def start_in state
      @current = self.class.states.find { |s| s.name == state.to_sym }
      start
    end

    def run_loop
      loop do
        current_state.call self
        break unless @status == :running
      end
    rescue => ex
      # leave_wait
      @status = :failed
      @exception = ex
      push event: Failed.new(source: self)
      raise ex
    end

    def move_to state
      Literal.check state, Symbol
      from = current_state
      @current = index_for_state state
      push event: Transitioned.new(source: self, from: from.name, via: "")
      state
    end

    def move_to_next_state = move_to(next_state)

    def wait
      @status = :waiting
    end

    def completed
      @status = :completed
      stop
    end

    private def before_start
      raise Plumbing::Actor::NotSupported if has_waits? && !can_defer?

      instance_exec(&self.class.initialiser)
      @status = :running
      push event: Started.new(source: self)
    end

    private def after_start
      advance
    end

    private def after_stop
      push event: Completed.new(source: self)
    end

    private def index_for_state name
      Literal.check name, Symbol
      self.class.states.index { |s| s.name == name }
    end

    private def has_waits? = self.class.states.any? { |state| state.is_a? Definitions::Wait }
    private def can_defer? = Actor.can_defer?

    def stale_poll?(token) = !token.nil? && token != @wait_generation

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def enter_wait(state)
      @waiting_state = state.name
      @wait_generation += 1
      @wait_started_at = monotonic - (@restored_wait_elapsed || 0.0)
      @restored_wait_elapsed = nil
      @timeout_id = after(state.wait_options.timeout, call: :advance, poll_token: @wait_generation)
      push event: Waiting.new(operation_id: object_id, state: state.name, attributes: attributes)
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
