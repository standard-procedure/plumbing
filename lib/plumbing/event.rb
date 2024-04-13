require "dry/types"
require "dry/struct"

module Plumbing
  class Event < Dry::Struct
    module Types
      include Dry::Types()
      SequenceNumber = Strict::Integer
      EventType = Strict::String
      EventData = Strict::Hash.default({}.freeze)
    end

    attribute :type, Types::EventType
    attribute :data, Types::EventData
  end
end
