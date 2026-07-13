# frozen_string_literal: true

require "async"
require_relative "worker"
require_relative "message"

module Plumbing
  module Actor
    # Processes an actor's messages on the Async reactor, ONE AT A TIME, IN
    # ARRIVAL ORDER — a single sequential consumer loop preserves the actor
    # guarantee.
    #
    # NOTE: we deliberately do NOT use `Async::Queue#async`. That spawns a new
    # task per item (bounded by a semaphore), so a single actor would deliver
    # several messages concurrently and complete them out of order — which
    # defeats the entire point of an actor. Concurrency belongs BETWEEN actors
    # (each has its own worker/queue/consumer), never within one.
    class Async < Worker
      prop :queue, ::Async::Queue, default: -> { ::Async::Queue.new }

      def start
        Kernel.Async(transient: true) do
          while (message = @queue.dequeue)
            message.deliver
          end
        end
      end

      def stop = @queue.close

      def active? = !@queue.closed?

      def dispatch(message) = @queue.enqueue(message)

      def can_defer? = true

      def after(delay, method:, sender: nil, params: {}, block: nil)
        message = build_message(method: method, params: params, block: block)
        deferral = Plumbing::Actor::Deferral.new
        Kernel.Async(transient: true) do |task|
          task.sleep delay
          dispatch(message) unless deferral.cancelled?
        end
        deferral
      end

      def message_class = Plumbing::Actor::Async::Message

      class Message < Actor::Message
        def _wait_until_ready
          sleep 0.001 while @status == :waiting
        end
      end
    end
  end
end

# Opt-in worker: requiring this file registers it. Select with
# `Plumbing::Actor.uses :async` (the app must also depend on the `async` gem).
Plumbing::Actor.register :async, can_defer: true do |actor|
  Plumbing::Actor::Async.new(actor: actor)
end
