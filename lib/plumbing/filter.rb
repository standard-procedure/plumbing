module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < Pipe
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Pipe]
    # @param &accepts [Block] a block that returns a boolean value - true to accept the event, false to reject it
    def initialize source:, dispatcher: nil, &accepts
      super(dispatcher: dispatcher)
      @accepts = accepts.as(Callable)
      source.as(Observable).add_observer do |event|
        filter_and_republish event
      end
    end

    private

    def filter_and_republish event
      return nil unless @accepts.call event
      dispatch event
    end
  end
end
