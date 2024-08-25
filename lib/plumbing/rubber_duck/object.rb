module Plumbing
  class RubberDuck
    ::Object.class_eval do
      def as duck_type
        duck_type.proxy_for self
      end
    end
  end
end
