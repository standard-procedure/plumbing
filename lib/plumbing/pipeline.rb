module Plumbing
  require_relative "pipeline/contracts"
  require_relative "pipeline/operations"

  # A chain of operations that are executed in sequence
  module Pipeline
    def self.included base
      base.extend Plumbing::Pipeline::Contracts
      base.extend Plumbing::Pipeline::Operations
    end

    # Start the pipeline operation with the given input
    # @param input [Object] the input data to be processed
    # @return [Object] the output data
    def call input
      self.class._call input, self
    end
  end
end
