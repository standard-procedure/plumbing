# frozen_string_literal: true

require_relative "worker"
require_relative "message"

module Plumbing
  module Actor
    # Processes an actor's messages on its own dedicated thread, ONE AT A TIME,
    # IN ARRIVAL ORDER. Concurrency is between actors (each has its own thread
    # and queue), never within one. Built on core Ruby — no concurrent-ruby.
    # Arguments are passed by reference — there is no marshalling / Ractor-safe
    # copying variant.
    #
    # The Worker is a frozen Literal::Data, so mutable state lives in container
    # objects (a Queue, a Mutex, a one-element Array holding the thread) rather
    # than reassignable ivars. Closing the queue makes `pop` return nil, which
    # cleanly stops the consumer.
    class Threaded < Worker
      prop :queue, _Any?, default: -> { Thread::Queue.new }
      prop :lock, _Any?, default: -> { Mutex.new }
      prop :runner, _Any?, default: -> { [] }

      def call
        @lock.synchronize { @runner << Thread.new { run_loop } if @runner.empty? }
        self
      end
      alias_method :start, :call

      def stop = @queue.close

      def active? = !@queue.closed?

      def dispatch(message)
        call
        @queue.push(message)
      end

      def after(delay, method:, sender: nil, params: {}, block: nil)
        call
        message = build_message(method: method, sender: sender, params: params, block: block)
        deferral = Plumbing::Actor::Deferral.new
        Thread.new do
          sleep delay
          dispatch(message) unless deferral.cancelled?
        end
        deferral
      end

      def message_class = Plumbing::Actor::Threaded::Message

      private

      def run_loop
        while (message = @queue.pop)
          message.deliver
        end
      end

      class Message < Actor::Message
        prop :ready, _Any?, default: -> { Thread::Queue.new }

        def deliver
          super
        ensure
          @ready.close # wakes the awaiting thread
        end

        def _wait_until_ready = @ready.pop # blocks until deliver closes it
      end
    end
  end
end

# Opt-in worker: requiring this file registers it. Select with
# `Plumbing::Actor.uses :threaded` (no extra gem needed — core Ruby threads).
Plumbing::Actor.register(:threaded) { |actor| Plumbing::Actor::Threaded.new(actor: actor) }
