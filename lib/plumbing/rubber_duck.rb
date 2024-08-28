module Plumbing
  # A type-checker for duck-types
  class RubberDuck
    require_relative "rubber_duck/object"
    require_relative "rubber_duck/proxy"

    def initialize *methods
      @methods = methods.map(&:to_sym)
      @proxy_classes = {}
    end

    # Verify that the given object responds to the required methods
    # @param object [Object] the object to verify
    # @return [Object] the object if it passes the verification
    # @raise [TypeError] if the object does not respond to the required methods
    def verify object
      missing_methods = @methods.reject { |method| object.respond_to? method }
      raise TypeError, "Expected object to respond to #{missing_methods.join(", ")}" unless missing_methods.empty?
      object
    end

    # Test if the given object is a proxy
    # @param object [Object] the object to test
    # @return [Boolean] true if the object is a proxy, false otherwise
    def proxy_for object
      is_a_proxy?(object) || build_proxy_for(object)
    end

    # Define a new rubber duck type
    # @param *methods [Array<Symbol>] the methods that the duck-type should respond to
    def self.define *methods
      new(*methods)
    end

    private

    def is_a_proxy? object
      @proxy_classes.value?(object.class) ? object : nil
    end

    def build_proxy_for object
      proxy_class_for(object).new(verify(object), self)
    end

    def proxy_class_for object
      @proxy_classes[object.class] ||= define_proxy_class_for(object.class)
    end

    def define_proxy_class_for klass
      Class.new(Plumbing::RubberDuck::Proxy).tap do |proxy_class|
        @methods.each do |method|
          proxy_class.define_method method do |*args, &block|
            @target.send method, *args, &block
          end
        end
      end
    end
  end
end
