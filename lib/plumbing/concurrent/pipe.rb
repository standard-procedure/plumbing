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
        @pipe = Ractor.new(self) do |instance|
          while (message = Ractor.receive) != :shutdown
            case message.first
            when :add_observer then instance.send :add_observing_ractor, message.last
            when :remove_observer then instance.send :remove_observing_ractor, message.last
            else instance.send :dispatch, message.last
            end
          end
        end
      end

      def add_observer ractor = nil, &block
        Plumbing::Concurrent::Pipe::Types::Observer[ractor].tap do |observer|
          @pipe << [:add_observer, observer]
        end
      end

      def << event
        @pipe << [:dispatch, Plumbing::BlockedPipe::Types::Event[event]]
      end

      def shutdown
        @pipe << :shutdown
        super
      end

      protected

      def dispatch event
        @observers.each do |observer|
          observer << event
        end
      end

      private

      def add_observing_ractor observer
        @observers << observer
      end

      def remove_observing_ractor observer
        @observers.delete observer
      end
    end
  end
end
