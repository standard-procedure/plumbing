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

      # Define the queries that this valve can answer
      # @param names [Array<Symbol>] the names of the queries
      def query(*names) = queries.concat(names.map(&:to_sym))

      # List the queries that this valve can answer
      def queries = @queries ||= []

      # Define the commands that this valve can execute
      # @param names [Array<Symbol>] the names of the commands
      def command(*names) = commands.concat(names.map(&:to_sym))

      # List the commands that this valve can execute
      def commands = @commands ||= []

      def inherited subclass
        subclass.commands.concat commands
        subclass.queries.concat queries
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
          queries.each do |query|
            proxy_class.define_method query do |*args, **params, &block|
              ask(query, *args, **params, &block)
            end
          end

          commands.each do |command|
            proxy_class.define_method command do |*args, **params, &block|
              tell(command, *args, **params, &block)
              nil
            rescue
              nil
            end
          end
        end
      end
    end
  end
end
