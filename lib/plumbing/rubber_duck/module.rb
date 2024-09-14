module Plumbing
  class RubberDuck
    ::Module.class_eval do
      def rubber_duck
        @rubber_duck ||= Plumbing::RubberDuck.define(*instance_methods)
      end

      def proxy_for object
        rubber_duck.proxy_for object
      end
    end
  end
end
