module Plumbing
  # A pipe that can be subclassed to filter events from a source pipe
  class Pipe::CustomFilter < Pipe
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Observable] the source from which to receive and filter events
    def initialize source:
      super()
      source.as(Observable).add_observer { |event_name, **data| received event_name, **data }
    end

    protected

    def received(event_name, **data) = raise NoMethodError.new("Subclass should define #received")
  end
end
