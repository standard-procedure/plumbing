require "dry/types"
require "dry/struct"

module Plumbing
  # An immutable data structure representing an Event
  class Event < Dry::Struct
    module Types
      include Dry::Types()
      SequenceNumber = Strict::Integer
      Type = Strict::String
      Data = Strict::Hash.map(Coercible::Symbol, Nominal::Any).default({}.freeze)
    end

    attribute :type, Types::Type
    attribute :data, Types::Data
  end
end
