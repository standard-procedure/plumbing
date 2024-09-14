module Plumbing
  class RubberDuck
    ::Object.class_eval do
      # Cast the object to a duck-type
      # @param type [Plumbing::RubberDuck, Module]
      # @return [Plumbing::RubberDuck::Proxy] the duck-type proxy
      def as type
        Plumbing::RubberDuck.cast self, type: type
      end
    end
  end
end
