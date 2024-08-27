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

      def self.start target
        new(target)
      end
    end
  end
end
