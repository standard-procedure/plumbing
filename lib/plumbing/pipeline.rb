require_relative "pipeline/contracts"
require_relative "pipeline/operations"

module Plumbing
  # A chain of operations that are executed in sequence
  class Pipeline
    extend Plumbing::Pipeline::Contracts
    extend Plumbing::Pipeline::Operations

    def call input
      self.class._call input, self
    end
  end
end
