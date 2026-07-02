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
require_relative "plumbing/object"
require_relative "plumbing/actor"
require_relative "plumbing/provider"
require_relative "plumbing/event"
require_relative "plumbing/pipeline"
require "timeout"

module Kernel
  def Await(duration = 60, &block)
    result = block.call
    Timeout.timeout(duration) do
      result.is_a?(Plumbing::Awaitable) ? result.await : result
    end
  end
  alias_method :await, :Await
end
