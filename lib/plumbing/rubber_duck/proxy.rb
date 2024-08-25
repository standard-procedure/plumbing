module Plumbing
  class RubberDuck
    class Proxy
      attr_reader :target
      def initialize target
        @target = target
      end
    end
  end
end
