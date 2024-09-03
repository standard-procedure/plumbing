require "async"
require "async/semaphore"
require "timeout"

module Plumbing
  module Valve
    class Async
      attr_reader :target

      def initialize target
        @target = target
        @queue = []
        @semaphore = ::Async::Semaphore.new(1)
      end

      # Ask the target to answer the given message
      def ask(message, *args, **params, &block)
        task = @semaphore.async do
          @target.send message, *args, **params, &block
        end
        Timeout.timeout(timeout) do
          task.wait
        end
      end

      # Tell the target to execute the given message
      def tell(message, *args, **params, &block)
        @semaphore.async do |task|
          @target.send message, *args, **params, &block
        rescue
          nil
        end
        nil
      end

      private

      def timeout
        Plumbing.config.timeout
      end
    end
  end
end
