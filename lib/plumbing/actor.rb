# frozen_string_literal: true

require_relative "actor/configuration"
require_relative "actor/definitions"
require_relative "actor/inline"

module Plumbing
  module Actor
    extend Configuration

    FIBER_KEY = :plumbing_actor_sender_stack

    # Raised when an actor asks for a capability its worker cannot provide
    # (e.g. deferring a message on the inline worker).
    NotSupported = Class.new(StandardError)

    # The actor that sent the message currently being processed (the top of the
    # sender stack), or nil. Set per-message by Message#deliver via a fiber-local
    # stack — safe under the Async worker because each delivery runs in its own
    # Async::Task fiber.
    def current_sender = (Fiber[FIBER_KEY] || []).last

    # The full synchronous sender chain, outermost first. Under the inline
    # worker this is the complete nested call-chain; under async each hop runs in
    # its own fiber, so it holds the immediate sender only.
    def current_senders = (Fiber[FIBER_KEY] || []).dup

    # Ask the worker to deliver `call` to this actor after `delay` seconds.
    # Returns a Plumbing::Actor::Deferral that can be passed to cancel_deferred.
    def after(delay, call:, sender: nil, **params, &block)
      worker.after(delay, method: call, sender: sender, params: params, block: block)
    end

    # Cancel a deferral returned by #after.
    def cancel_deferred(deferral) = worker.cancel_deferred(deferral)

    def start = worker.start
    # Shut this actor down by closing its worker's queue: any already-queued
    # messages still run, then the consumer thread / async task exits rather
    # than blocking forever. Whoever owns the actor's lifecycle calls this; the
    # inline worker has nothing to stop, so it's a no-op there. An actor that
    # defines its own async `:stop` message shadows this method.
    def stop = worker.stop

    def self.included klass
      klass.extend Definitions
      klass.extend Literal::Properties
      klass.prop :worker, Plumbing::Actor::Worker, default: -> { Plumbing::Actor.worker_for self }, reader: :public, writer: false
    end

    def self.start(*)
      new(*).tap do |actor|
        actor.start
      end
    end
  end
end
