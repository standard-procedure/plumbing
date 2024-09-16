require "async"
require "async/semaphore"
require "timeout"

module Plumbing
  module Actor
    class Async
      attr_reader :target

      def initialize target
        @target = target
        @queue = []
        @semaphore = ::Async::Semaphore.new(1)
      end

      # Send the message to the target and wrap the result
      def send_message message_name, *args, &block
        task = @semaphore.async do
          @target.send message_name, *args, &block
        end
        Result.new(task)
      end

      def safely(&)
        send_message(:perform_safely, &)
        nil
      end

      def within_actor? = true

      def stop
        # do nothing
      end

      Result = Data.define(:task) do
        def value
          Timeout.timeout(Plumbing::Actor.timeout) do
            task.wait
          end
        end
      end
      private_constant :Result
    end

    def self.timeout
      Plumbing.config.timeout
    end
  end
end
