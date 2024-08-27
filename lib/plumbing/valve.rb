require_relative "valve/inline"

module Plumbing
  module Valve
    def query name
      queries << name.to_sym
    end

    def command name
      commands << name.to_sym
    end

    def start(*, **, &)
      build_proxy_for new(*, **, &)
    end

    def queries
      @queries ||= []
    end

    def commands
      @commands ||= []
    end

    private

    def build_proxy_for target
      proxy_class.start(target)
    end

    def proxy_class
      Plumbing.config.valve_proxy_class_for(self.class) || register_valve_proxy_class
    end

    def proxy_base_class
      class_name = Plumbing.config.mode.to_s.capitalize
      const_get "Plumbing::Valve::#{class_name}"
    end

    def register_valve_proxy_class
      Plumbing.config.register_valve_proxy_class_for(self.class, build_proxy_class)
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
          end
        end
      end
    end
  end
end
