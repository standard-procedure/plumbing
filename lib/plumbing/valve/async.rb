require "async"
require_relative "message"
require "timeout"

module Plumbing
  module Valve
    class Async
      attr_reader :target

      def initialize target
        @target = target
        @queue = []
        @task = Kernel.Async(transient: true) do
          dispatch_messages
        end
      end

      def ask(message, *args, **params, &block)
        message = Message.new(message, args, params, block)
        @queue << message
        Timeout.timeout(timeout) do
          while message.status.nil?
            sleep 0.1
          end
          (message.status == :success) ? message.result : raise(message.result)
        end
      end

      def tell(message, *args, **params, &block)
        @queue << Message.new(message, args, params, block)
        nil
      end

      def self.start target
        new(target)
      end

      private

      def dispatch_messages
        loop do
          message = @queue.shift
          dispatch message unless message.nil?
          sleep 0.1
        end
      end

      def dispatch message
        message.result = @target.send(message.message, *message.args, **message.params, &message.block)
        message.status = :success
      rescue => ex
        message.result = ex
        message.status = :failed
      end

      def timeout
        Plumbing.config.timeout
      end
    end
  end
end
