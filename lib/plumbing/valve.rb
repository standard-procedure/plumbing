require_relative "valve/kernel"
require_relative "valve/inline"

module Plumbing
  module Valve
    def self.included base
      base.extend ClassMethods
    end

    module ClassMethods
      # Create a new valve instance and build a proxy for it using the current mode
      # @return [Plumbing::Valve::Base] the proxy for the valve instance
      def start(*, **, &)
        build_proxy_for(new(*, **, &))
      end

      # Define the async messages that this valve can respond to
      # @param names [Array<Symbol>] the names of the async messages
      def async(*names) = async_messages.concat(names.map(&:to_sym))

      # List the async messages that this valve can respond to
      def async_messages = @async_messages ||= []

      def inherited subclass
        subclass.async_messages.concat async_messages
      end

      private

      def build_proxy_for(target)
        proxy_class_for(target.class).new(target)
      end

      def proxy_class_for target_class
        Plumbing.config.valve_proxy_class_for(target_class) || register_valve_proxy_class_for(target_class)
      end

      def proxy_base_class = const_get "Plumbing::Valve::#{Plumbing.config.mode.to_s.capitalize}"

      def register_valve_proxy_class_for target_class
        Plumbing.config.register_valve_proxy_class_for(target_class, build_proxy_class)
      end

      def build_proxy_class
        Class.new(proxy_base_class).tap do |proxy_class|
          async_messages.each do |message|
            proxy_class.define_method message do |*args, &block|
              send_message(message, *args, &block)
            end
          end
        end
      end
    end
  end
end
