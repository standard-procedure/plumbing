module Plumbing
  module Valve
    class Inline
      def initialize target
        @target = target
      end

      def ask(message, ...)
        @target.send(message, ...)
      end

      def tell(message, ...)
        @target.send(message, ...)
      end
    end
  end
end
