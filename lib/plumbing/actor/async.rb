require "async"
require "async/semaphore"
require "timeout"

module Plumbing
  module Actor
    class Async
      attr_reader :target

      def initialize target
        @target = target
        @semaphore = ::Async::Semaphore.new(Plumbing.config.max_concurrency)
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *args, **params, &block)
        Plumbing.config.logger.debug { "-> #{@target.class}##{message_name}(#{args.inspect}, #{params.inspect})" }
        task = @semaphore.async do
          Plumbing.config.logger.debug { "---> #{@target.class}##{message_name}(#{args.inspect}, #{params.inspect})" }
          @target.send(message_name, *args, **params, &block)
        end
        sleep 0.01
        Result.new(task)
      end

      def safely(&)
        Plumbing.config.logger.debug { "-> #{@target.class}#perform_safely" }
        send_message(:perform_safely, &)
        sleep 0.01
        nil
      end

      def in_context? = true

      def stop = nil

      Result = Data.define(:task) do
        def value
          sleep 0.01
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
