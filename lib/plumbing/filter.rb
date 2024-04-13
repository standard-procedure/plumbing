require "dry/types"
require_relative "pipe"

module Plumbing
  class Filter < Pipe
    module Types
      include Dry::Types()
      Source = Instance(Plumbing::Pipe)
      EventTypes = Array.of(Plumbing::Event::Types::EventType)
    end

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
      self << event
    end
  end
end
