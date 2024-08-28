module Plumbing
  # A pipe that can be subclassed to filter events from a source pipe
  class CustomFilter < Pipe
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Observable] the source from which to receive and filter events
    def initialize source:
      super()
      source.as(Observable).add_observer { |event| received event }
    end

    protected

    def received(event) = raise NoMethodError.new("Subclass should define #received")
  end
end
