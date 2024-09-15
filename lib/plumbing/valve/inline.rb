module Plumbing
  module Valve
    class Inline
      def initialize target
        @target = target
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *, &)
        result = @target.send(message_name, *, &)
        Result.new(result)
      rescue => ex
        Result.new(ex)
      end

      Result = Data.define(:result) do
        def value
          raise result if result.is_a? Exception
          result
        end
      end
      private_constant :Result
    end
  end
end
