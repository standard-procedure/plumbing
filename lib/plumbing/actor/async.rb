# frozen_string_literal: true

require "async"
require "async/semaphore" # not autoloaded by `require "async"` on async < ~2.39
require_relative "worker"
require_relative "message"

module Plumbing
  module Actor
    class Async < Worker
      prop :queue, ::Async::Queue, default: -> { ::Async::Queue.new }
      prop :active, _Boolean, default: true
      prop :limit, _Integer(1..64), default: 8
      prop :timeout, _Integer(0..3600), default: 30

      def call
        Kernel.Async(transient: true) do |loop|
          semaphore = ::Async::Semaphore.new(@limit, parent: loop)
          @queue.async(parent: semaphore) { |_task, message| message.deliver }
        end
      end

      def stop
        @active = false
        @queue.close
      end

      def active? = @active

      def dispatch(message) = @queue.push(message)

      def message_class = Plumbing::Actor::Async::Message

      class Message < Actor::Message
        prop :timeout, _Integer(0..3600), default: -> { @actor.worker.timeout }

        def _wait_until_ready
          sleep 0.001 while @status == :waiting
        end
      end
    end
  end
end

# Opt-in worker: requiring this file registers it. Select with
# `Plumbing::Actor.uses :async` (the app must also depend on the `async` gem).
Plumbing::Actor.register(:async) { |actor| Plumbing::Actor::Async.new(actor: actor) }
