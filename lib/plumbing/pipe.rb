require "dry/types"
require_relative "event"

module Plumbing
  InvalidEvent = Dry::Types::ConstraintError
  InvalidObserver = Dry::Types::ConstraintError

  class Pipe
    module Types
      include Dry::Types()
      Event = Instance(Plumbing::Event)
      Observer = Interface(:call)
    end

    def initialize
      @observers = []
      @fiber = Fiber.new do |event|
        loop do
          break if event == :shutdown
          @observers.each do |observer|
            observer.call event
          end
          event = Fiber.yield
        end
      end
    end

    def << event
      @fiber.resume Types::Event[event]
    end

    def add_observer callable = nil, &block
      callable ||= block.to_proc
      Types::Observer[callable].tap do |observer|
        @observers << observer
      end
    end

    def remove_observer callable
      @observers.delete callable
    end

    def self.start(**params)
      new(**params)
    end
  end
end
