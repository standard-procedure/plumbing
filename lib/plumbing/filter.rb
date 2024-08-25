module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < Pipe
    # Chain this pipe to the source pipe
    # @param source [Plumbing::Pipe]
    # @param &accepts [Block] a block that returns a boolean value - true to accept the event, false to reject it
    def initialize source:, &accepts
      super()
      raise InvalidSource.new "#{source} must be a Plumbing::Pipe descendant" unless source.is_a? Plumbing::Pipe
      @accepts = accepts
      source.add_observer do |event|
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
