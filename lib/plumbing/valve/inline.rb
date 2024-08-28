module Plumbing
  module Valve
    class Inline
      def initialize target
        @target = target
      end

      # Ask the target to answer the given message
      def ask(message, ...)
        @target.send(message, ...)
      end

      # Tell the target to execute the given message
      def tell(message, ...)
        @target.send(message, ...)
      end
    end
  end
end
