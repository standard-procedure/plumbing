module Plumbing
  module Actor
    class Inline
      def initialize target
        @target = target
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *, &)
        value = @target.send(message_name, *, &)
        Result.new(value)
      rescue => ex
        Result.new(ex)
      end

      def safely(&)
        send_message(:perform_safely, &)
        nil
      end

      def within_actor? = true

      def stop
        # do nothing
      end

      Result = Data.define(:result) do
        def value = result.is_a?(Exception) ? raise(result) : result
      end
      private_constant :Result
    end
  end
end
