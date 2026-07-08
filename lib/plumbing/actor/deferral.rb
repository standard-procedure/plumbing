# frozen_string_literal: true

module Plumbing
  module Actor
    # An opaque handle for a scheduled (deferred) message. Cancelling sets a
    # mutex-guarded flag that the worker's timer checks before dispatching. The
    # flag itself is race-safe; a cancel landing in the tiny window after the
    # check still lets one (benign, in-order) message through — the operation
    # layer's generation token discards such a stale fire.
    class Deferral < Literal::Struct
      prop :lock, Mutex, default: -> { Mutex.new }, reader: :private, writer: false
      prop :cancelled, _Boolean, default: -> { false }, reader: :private, writer: false

      def cancel = @lock.synchronize { @cancelled = true }

      def cancelled? = @lock.synchronize { @cancelled }
    end
  end
end
