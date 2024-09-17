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
        @mutex = Thread::Mutex.new
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *args, **params, &block)
        Message.new(@target, message_name, Plumbing::Actor.transporter.marshal(*args, **params), block, Concurrent::MVar.new).tap do |message|
          @mutex.synchronize do
            @queue << message
            send_messages if @queue.any?
          end
        end
      end

      def safely(&)
        send_message(:perform_safely, &)
        nil
      end

      def within_actor? = @mutex.owned?

      def stop
        within_actor? ? @queue.clear : @mutex.synchronize { @queue.clear }
      end

      protected

      def future(&) = Concurrent::Promises.future(&)

      private

      def send_messages
        future do
          @mutex.synchronize do
            message = @queue.shift
            message&.call
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

        def value
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
