# frozen_string_literal: true

module Kernel
  def Await(duration = 60, &block)
    result = block.call
    Timeout.timeout(duration) do
      result.is_a?(Plumbing::Awaitable) ? result.await : result
    end
  end
  alias_method :await, :Await
end
