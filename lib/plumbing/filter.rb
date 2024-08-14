module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < BlockedPipe
    class InvalidFilter < Error; end

    # Chain this pipe to the source pipe
    # @param source [Plumbing::BlockedPipe]
    # @param accepts [Array[String]] event types that this filter will allow through (or pass [] to allow all)
    # @param rejects [Array[String]] event types that this filter will not allow through
    def initialize source:, accepts: [], rejects: []
      super()
      raise InvalidFilter.new "source must be a Plumbing::BlockedPipe descendant" unless source.is_a? Plumbing::BlockedPipe
      raise InvalidFilter.new "accepts and rejects must be arrays" unless accepts.is_a?(Array) && rejects.is_a?(Array)
      @accepted_event_types = accepts
      @rejected_event_types = rejects
      source.add_observer do |event|
        filter_and_republish(event)
      end
    end

    private

    def filter_and_republish event
      raise InvalidEvent.new "event is not a Plumbing::Event" unless event.is_a? Plumbing::Event
      return nil if @accepted_event_types.any? && !@accepted_event_types.include?(event.type)
      return nil if @rejected_event_types.include? event.type
      dispatch event
    end
  end
end
