# frozen_string_literal: true

require_relative "pipeline"

module Plumbing
  # Mix into any object — actor or not — to give it an observable event stream.
  # The host gains a public subscriber interface (observe / remove / remove_all)
  # and a private emit interface (push / notify), both backed by a lazily-created
  # internal Plumbing::Pipeline::Source.
  #
  # The pipeline is itself the actor, so these methods need not be async: they
  # forward to the pipeline's async messages fire-and-forget, returning the
  # awaitable (await it if you need the result — e.g. the observer proc that
  # #remove expects).
  module Observable
    # Register an observer block. Returns the awaitable that yields the observer
    # proc (hand that proc to #remove later).
    def observe(&observer) = pipeline.observe(&observer)

    # Deregister a previously-registered observer proc.
    def remove(observer) = @pipeline&.remove(observer: observer)

    # Deregister every observer.
    def remove_all = @pipeline&.remove_all

    # Emit an event object to the observers.
    private def push(event) = @pipeline&.push(event: event)

    # Build a registered event from its type name and emit it.
    private def notify(event_type, **params) = @pipeline&.notify(event_type: event_type, params: params)

    # The internal pipeline, created on first observe. Left nil until something
    # observes, so an unobserved host stays cheap and emits nowhere.
    private def pipeline = @pipeline ||= Plumbing::Pipeline::Source.new

    def self.included klass
      klass.extend Literal::Properties
      klass.prop :pipeline, Literal::Types._Nilable(Plumbing::Pipeline::Source), reader: false, writer: false
    end
  end
end
