module Plumbing
  class RubberDuck
    ::Object.class_eval do
      # Cast the object to a duck-type
      # @return [Plumbing::RubberDuck::Proxy] the duck-type proxy
      def as duck_type
        duck_type.proxy_for self
      end
    end
  end
end
