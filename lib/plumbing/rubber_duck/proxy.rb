module Plumbing
  class RubberDuck
    # Proxy object that forwards the duck-typed methods to the target object
    class Proxy
      attr_reader :target

      def initialize target, duck_type
        @target = target
        @duck_type = duck_type
      end

      # Convert the proxy to the given duck-type, ensuring that existing proxies are not duplicated
      # @return [Plumbing::RubberDuck::Proxy] the proxy for the given duck-type
      def as duck_type
        (duck_type == @duck_type) ? self : duck_type.proxy_for(target)
      end
    end
  end
end
