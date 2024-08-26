require_relative "custom_filter"
module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < CustomFilter
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Pipe]
    # @param &accepts [Block] a block that returns a boolean value - true to accept the event, false to reject it
    def initialize source:, dispatcher: nil, &accepts
      super(source: source, dispatcher: dispatcher)
      @accepts = accepts.as(Callable)
    end

    protected

    def received(event)
      return nil unless @accepts.call event
      dispatch event
    end
  end
end
