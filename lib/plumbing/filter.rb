require "dry/types"
require_relative "blocked_pipe"

module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < BlockedPipe
    module Types
      include Dry::Types()
      Source = Instance(Plumbing::BlockedPipe)
      EventTypes = Array.of(Plumbing::Event::Types::Type)
    end

    # Chain this pipe to the source pipe
    # @param source [Plumbing::BlockedPipe]
    # @param accepts [Array[String]] event types that this filter will allow through (or pass [] to allow all)
    # @param rejects [Array[String]] event types that this filter will not allow through
    def initialize source:, accepts: [], rejects: []
      super()
      @accepted_event_types = Types::EventTypes[accepts]
      @rejected_event_types = Types::EventTypes[rejects]
      Types::Source[source].add_observer do |event|
        filter_and_republish(event)
      end
    end

    private

    def filter_and_republish event
      return nil if @accepted_event_types.any? && !@accepted_event_types.include?(event.type)
      return nil if @rejected_event_types.include? event.type
      dispatch event
    end
  end
end
