require_relative "custom_filter"
module Plumbing
  # A pipe that filters events from a source pipe
  class Pipe::Filter < Pipe::CustomFilter
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Observable] the source from which to receive and filter events
    # @param &accepts [Block] a block that returns a boolean value - true to accept the event, false to reject it
    # @yield [Plumbing::Event] event the event that is currently being processed
    # @yieldreturn [Boolean] true to accept the event, false to reject it
    def initialize source:, &accepts
      super(source: source)
      @accepts = accepts.as(Callable)
    end

    protected

    def received(event_name, **data)
      return nil unless @accepts.call event_name, **data
      notify event_name, **data
    end
  end
end
