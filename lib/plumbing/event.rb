require_relative "error"

module Plumbing
  # An immutable data structure representing an Event
  class Event
    def initialize type:, data: {}
      raise InvalidEvent.new("Type is invalid #{type}") unless String === type
      raise InvalidEvent.new("Data is invalid #{data.class}") unless Hash === data
      @type = type.freeze
      @data = data.freeze
    end

    attr_reader :type
    attr_reader :data
  end
end
