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

      Result = Data.define(:value) do
        def await = value.is_a?(Exception) ? raise(value) : value
      end
      private_constant :Result
    end
  end
end
