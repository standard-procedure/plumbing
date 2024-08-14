require "dry/types"
require_relative "../blocked_pipe"

module Plumbing
  module Concurrent
    class Pipe < Plumbing::BlockedPipe
      module Types
        include Dry::Types()
        # Observers must be Ractors
        Observer = Instance(Ractor)
      end

      def initialize
        super
        @queue = Ractor.new(self) do |instance|
          while (message = Ractor.receive) != :shutdown
            case message.first
            when :add_observer then instance.send :add_observing_ractor, message.last
            when :is_observer? then Ractor.yield(instance.send(:is_observing_ractor?, message.last))
            when :remove_observer then instance.send :remove_observing_ractor, message.last
            else instance.send :dispatch, message.last
            end
          end
        end
      end

      def add_observer ractor = nil, &block
        Plumbing::Concurrent::Pipe::Types::Observer[ractor].tap do |observer|
          @queue << [:add_observer, observer]
        end
      end

      def remove_observer ractor = nil, &block
        @queue << [:remove_observer, ractor]
      end

      def is_observer? ractor
        @queue << [:is_observer?, ractor]
        @queue.take
      end

      def << event
        @queue << [:dispatch, Plumbing::BlockedPipe::Types::Event[event]]
      end

      def shutdown
        @queue << :shutdown
        super
      end

      private

      def dispatch event
        @observers.each do |observer|
          observer << event
        end
      end

      def add_observing_ractor observer
        @observers << observer
      end

      def is_observing_ractor? observer
        @observers.include? observer
      end

      def remove_observing_ractor observer
        @observers.delete observer
      end
    end
  end
end
