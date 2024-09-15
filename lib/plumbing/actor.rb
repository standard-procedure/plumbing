require_relative "actor/kernel"
require_relative "actor/inline"

module Plumbing
  module Actor
    def self.included base
      base.extend ClassMethods
    end

    module ClassMethods
      # Create a new actor instance and build a proxy for it using the current mode
      # @return [Object] the proxy for the actor instance
      def start(*, **, &)
        build_proxy_for(new(*, **, &))
      end

      # Define the async messages that this actor can respond to
      # @param names [Array<Symbol>] the names of the async messages
      def async(*names) = async_messages.concat(names.map(&:to_sym))

      # List the async messages that this actor can respond to
      def async_messages = @async_messages ||= []

      def inherited subclass
        subclass.async_messages.concat async_messages
      end

      private

      def build_proxy_for(target)
        proxy_class_for(target.class).new(target)
      end

      def proxy_class_for target_class
        Plumbing.config.actor_proxy_class_for(target_class) || register_actor_proxy_class_for(target_class)
      end

      def proxy_base_class = const_get PROXY_BASE_CLASSES[Plumbing.config.mode]

      PROXY_BASE_CLASSES = {
        inline: "Plumbing::Actor::Inline",
        async: "Plumbing::Actor::Async",
        threaded: "Plumbing::Actor::Threaded",
        rails: "Plumbing::Actor::Rails"
      }.freeze
      private_constant :PROXY_BASE_CLASSES

      def register_actor_proxy_class_for target_class
        Plumbing.config.register_actor_proxy_class_for(target_class, build_proxy_class)
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
