# frozen_string_literal: true

require "literal"

module Plumbing
  class Error < StandardError; end

  # Marker for things that can be `await`-ed via Kernel#Await.
  # Including this module advertises that the host class has a real `#await`
  # method. We can't use `respond_to?(:await)` to detect this because
  # `Kernel#Await` is aliased to `Kernel#await`, so every object responds to it.
  module Awaitable; end
end

require_relative "plumbing/version"
require_relative "plumbing/types"

module Kernel
  def Await(&block)
    result = block.call
    result.is_a?(Plumbing::Awaitable) ? result.await : result
  end
  alias_method :await, :Await
end
