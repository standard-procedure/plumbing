require "concurrent/array"
require "concurrent/mvar"
require "concurrent/immutable_struct"
require "concurrent/promises"

module Plumbing
  module Valve
    class Threaded
      attr_reader :target

      def initialize target
        @target = target
        @queue = Concurrent::Array.new
      end

      # Ask the target to answer the given message
      def ask(message, *, **, &)
        add_message_to_queue(message, *, **, &).value
      end

      # Tell the target to execute the given message
      def tell(message, *, **, &)
        add_message_to_queue(message, *, **, &)
        nil
      rescue
        nil
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

      def add_message_to_queue message_name, *args, **params, &block
        Message.new(@target, message_name, args, params, block, Concurrent::MVar.new).tap do |message|
          @queue << message
          send_messages if @queue.size == 1
        end
      end

      class Message < Concurrent::ImmutableStruct.new(:target, :name, :args, :params, :block, :result)
        def value
          result.take(Plumbing.config.timeout).tap do |value|
            raise value if value.is_a? Exception
          end
        end

        def call
          result.put target.send(name, *args, **params, &block)
        rescue => ex
          result.put ex
        end
      end
    end
  end
end
