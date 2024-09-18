module Plumbing
  module Actor
    class Inline
      def initialize target
        @target = target
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *args, **params, &)
        Plumbing.config.logger.debug { "-> #{@target.class}##{message_name}(#{args.inspect}, #{params.inspect})" }
        Plumbing.config.logger.debug { "---> #{@target.class}##{message_name}(#{args.inspect}, #{params.inspect})" }
        value = @target.send(message_name, *args, **params, &)
        Plumbing.config.logger.debug { "===> #{@target.class}##{message_name} => #{value}" }
        Result.new(value)
      rescue => ex
        Plumbing.config.logger.debug { "!!!! #{@target.class}##{message_name} => #{ex}" }
        Result.new(ex)
      end

      def safely(&)
        Plumbing.config.logger.debug { "-> #{@target.class}#perform_safely" }
        send_message(:perform_safely, &)
        nil
      end

      def in_context? = true

      def stop = nil

      Result = Data.define(:result) do
        def value = result.is_a?(Exception) ? raise(result) : result
      end
      private_constant :Result
    end
  end
end
