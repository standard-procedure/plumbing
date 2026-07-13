# frozen_string_literal: true

require_relative "event"

module Plumbing
  class Pipeline
    include Plumbing::Actor

    prop :observers, _Array(_Callable), default: -> { [] }, reader: :private, writer: false
    prop :queue, _Array(Plumbing::Event), default: -> { [] }, reader: :private, writer: false
    prop :seen, Set, default: -> { Set.new }, reader: :private, writer: false
    prop :draining, _Boolean, default: -> { false }, reader: :private, writer: false

    async :add_observer do
      calls do |&observer|
        @observers << observer
        observer
      end
    end

    async :remove_observer do
      param :observer, _Callable

      calls do |observer:|
        @observers.delete observer
        observer
      end
    end

    async :remove_all_observers do
      calls do
        @observers = []
      end
    end

    # Notify all observers of an event (optionally debounced)
    async :push do
      param :event, Plumbing::Event
      param :debounce, _Boolean, default: true
      calls do |event:, debounce:|
        enqueue(event, debounce)
        drain
        event
      end
    end
    # Emit an event (alias for #push). Returns the awaitable message.
    def <<(event) = push(event: event)

    # Build a registered event from its type name and notify observers
    async :build_and_push do
      param :event_type, String
      param :debounce, _Boolean, default: true
      param :source, Plumbing.Observable?, default: nil
      param :params, Hash, default: {}.freeze
      calls do |event_type:, debounce:, source:, params:|
        await { Plumbing::Event.types.build(event_type, source: source || self, **params) }.tap do |event|
          enqueue(event, debounce)
          drain
        end
      end
    end
    # Convenience method for build and push
    def notify event_type, debounce: true, source: nil, **params
      await { build_and_push event_type:, debounce:, source:, params: }
    end

    # Chain this pipeline to a source: observe the source and re-emit each
    # event for which the predicate block returns true. Used by the
    # Only/Except/Filter/Junction composition classes.
    protected def chain(source, &predicate)
      source.add_observer { |event| push(event: event) if predicate.call(event) }
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

require_relative "pipeline/only"
require_relative "pipeline/except"
require_relative "pipeline/filter"
require_relative "pipeline/junction"
