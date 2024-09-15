require "concurrent/array"
require "concurrent/mvar"
require "concurrent/immutable_struct"
require "concurrent/promises"
require_relative "transporter"

module Plumbing
  module Actor
    class Threaded
      attr_reader :target

      def initialize target
        @target = target
        @queue = Concurrent::Array.new
      end

      # Send the message to the target and wrap the result
      def send_message message_name, *args, &block
        Message.new(@target, message_name, Plumbing::Actor.transporter.marshal(*args), block, Concurrent::MVar.new).tap do |message|
          @queue << message
          send_messages if @queue.size == 1
        end
      end

      protected

      def future(&)
        Concurrent::Promises.future(&)
      end

      private

      def send_messages
        future do
          while (message = @queue.shift)
            message.call
          end
        end
      end

      class Message < Concurrent::ImmutableStruct.new(:target, :message_name, :packed_args, :unsafe_block, :result)
        def call
          args = Plumbing::Actor.transporter.unmarshal(*packed_args)
          value = target.send message_name, *args, &unsafe_block
          result.put Plumbing::Actor.transporter.marshal(value)
        rescue => ex
          result.put ex
        end

        def await
          value = Plumbing::Actor.transporter.unmarshal(*result.take(Plumbing.config.timeout)).first
          raise value if value.is_a? Exception
          value
        end
      end
    end

    def self.transporter
      @transporter ||= Plumbing::Actor::Transporter.new
    end
  end
end
