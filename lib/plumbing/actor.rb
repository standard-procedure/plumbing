# frozen_string_literal: true

require_relative "actor/configuration"
require_relative "actor/definitions"
require_relative "actor/inline"

module Plumbing
  module Actor
    extend Configuration

    FIBER_KEY = :plumbing_actor_sender_stack

    def initialize(...)
      super
      @worker = Plumbing::Actor.worker_for self
    end
    attr_reader :worker

    # The actor that sent the message currently being processed (the top of the
    # sender stack), or nil. Set per-message by Message#deliver via a fiber-local
    # stack — safe under the Async worker because each delivery runs in its own
    # Async::Task fiber.
    def current_sender = (Fiber[FIBER_KEY] || []).last

    # The full synchronous sender chain, outermost first. Under the inline
    # worker this is the complete nested call-chain; under async each hop runs in
    # its own fiber, so it holds the immediate sender only.
    def current_senders = (Fiber[FIBER_KEY] || []).dup

    def self.included klass
      klass.extend Definitions
    end
  end
end
