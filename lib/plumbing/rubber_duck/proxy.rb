module Plumbing
  class RubberDuck
    class Proxy
      attr_reader :target

      def initialize target, duck_type
        @target = target
        @duck_type = duck_type
      end

      def as duck_type
        (duck_type == @duck_type) ? self : duck_type.proxy_for(target)
      end
    end
  end
end
