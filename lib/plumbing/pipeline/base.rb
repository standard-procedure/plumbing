# frozen_string_literal: true

require_relative "../actor"
require_relative "../event"

module Plumbing
  class Pipeline
    # Abstract base for all pipelines. A pipeline is an actor, so its observer
    # list and event queue are safe under the concurrent workers. Observers are
    # procs, each called with every emitted event.
    class Base < Literal::Struct
      include Plumbing::Actor

      prop :observers, _Array(_Callable), default: -> { [] }, reader: :private, writer: false
      prop :queue, _Array(Plumbing::Event), default: -> { [] }, reader: :private, writer: false
      prop :seen, Set, default: -> { Set.new }, reader: :private, writer: false
      prop :draining, _Boolean, default: -> { false }, reader: :private, writer: false

      # Register an observer (passed as a block). Returns the proc so it can be
      # handed to #remove later.
      async :observe do
        calls { |&observer| @observers << observer }
      end

      # Deregister a previously-registered observer proc.
      async :remove do
        param :observer, Proc
        calls { |observer:| @observers.delete(observer) }
      end

      # Deregister every observer.
      async :remove_all do
        calls { @observers.clear }
      end

      # Emit an event. Value-equal duplicates are debounced within a drain cycle
      # unless debounce: false.
      async :push do
        param :event, Plumbing::Event
        param :debounce, _Boolean, default: true
        calls do |event:, debounce:|
          enqueue(event, debounce)
          drain
          event
        end
      end

      # Build a registered event from its type name and emit it.
      async :notify do
        param :event_type, String
        param :debounce, _Boolean, default: true
        param :params, Hash, default: {}.freeze
        calls do |event_type:, debounce:, params:|
          event = Plumbing::Pipeline.event_type(event_type).new(**params.merge(source: self))
          enqueue(event, debounce)
          drain
          event
        end
      end

      # Emit an event (alias for #push). Returns the awaitable message.
      def <<(event) = push(event: event)

      # Chain this pipeline to a source: observe the source and re-emit each
      # event for which the predicate block returns true. Used by the
      # Only/Except/Filter/Junction composition classes.
      protected def chain(source, &predicate)
        source.observe { |event| push(event: event) if predicate.call(event) }
        self
      end

      # Does `name` match any of the string filters? A trailing `*` is a prefix
      # wildcard ("Error*" matches "ErrorRaised").
      private def wildcard_match?(filters, name) = filters.any? { |filter| filter.end_with?("*") ? name.start_with?(filter[0..-2]) : name == filter }

      private def enqueue(event, debounce)
        @queue << event if !debounce || @seen.add?(event)
      end

      # Drain the queue, delivering every queued event to every observer, in
      # order. A re-entrant push (an observer that pushes) just enqueues — the
      # outermost drain owns the loop and the cleanup. `@seen` spans the whole
      # cycle, so duplicates coalesce across re-entrant pushes too.
      private def drain
        return if @draining
        @draining = true
        begin
          until @queue.empty?
            batch = @queue
            @queue = []
            batch.each { |event| @observers.each { |observer| observer.call(event) } }
          end
        ensure
          @seen.clear
          @draining = false
        end
      end
    end
  end
end
