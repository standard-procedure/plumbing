# frozen_string_literal: true

module Plumbing
  module Actor
    # An opaque handle for a scheduled (deferred) message. Cancelling sets a
    # flag that the worker's timer checks before dispatching, so a timer that
    # fires concurrently with a cancel simply does nothing (race-safe).
    class Deferral
      def initialize
        @lock = Mutex.new
        @cancelled = false
      end

      def cancel = @lock.synchronize { @cancelled = true }

      def cancelled? = @lock.synchronize { @cancelled }
    end
  end
end
