require_relative "chain/contracts"
require_relative "chain/operations"

module Plumbing
  # A chain of operations that are executed in sequence
  class Chain
    extend Plumbing::Chain::Contracts
    extend Plumbing::Chain::Operations

    def call input
      self.class._call input, self
    end
  end
end
