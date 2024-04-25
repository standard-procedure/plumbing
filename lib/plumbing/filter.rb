require_relative "blocked_pipe"

module Plumbing
  # A pipe that filters events from a source pipe
  class Filter < BlockedPipe
    # Chain this pipe to the source pipe
    # @param source [Plumbing::BlockedPipe]
    # @param accepts [Array[String]] event types that this filter will allow through (or pass [] to allow all)
    # @param rejects [Array[String]] event types that this filter will not allow through
    def initialize source:, accepts: [], rejects: []
      super()
      raise InvalidSource.new("Source is not Plumbing::BlockedPipe") unless Plumbing::BlockedPipe === source
      raise InvalidEvent.new("Accepted types are not [String]") unless array_of_strings? accepts
      raise InvalidEvent.new("Rejected types are not [String]") unless array_of_strings? rejects
      @accepts = accepts.freeze
      @rejects = rejects.freeze
      source.add_observer do |event|
        filter_and_republish(event)
      end
    end

    # Is this event acceptable to be processed by this filter?
    # @param [Plumbing::Event]
    # @return [boolean]
    def accepts? event
      return false if @accepts.any? && !@accepts.include?(event.type)
      return false if @rejects.include? event.type
      true
    end

    private

    def filter_and_republish event
      dispatch event if accepts? event
    end

    def array_of_strings? strings
      return false unless Enumerable === strings
      return false if strings.any? { |s| !s.is_a? String }
      true
    end
  end
end
