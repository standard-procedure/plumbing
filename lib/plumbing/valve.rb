require_relative "valve/inline"

module Plumbing
  module Valve
    def start(*, **, &)
      build_proxy_for(new(*, **, &))
    end

    def query(*names) = names.map(&:to_sym).each { |n| queries << n }

    def queries = @queries ||= []

    def command(*names) = names.map(&:to_sym).each { |n| commands << n }

    def commands = @commands ||= []

    private

    def build_proxy_for(target) = proxy_class.start(target)

    def proxy_class = Plumbing.config.valve_proxy_class_for(self.class) || register_valve_proxy_class

    def proxy_base_class = const_get "Plumbing::Valve::#{Plumbing.config.mode.to_s.capitalize}"

    def register_valve_proxy_class = Plumbing.config.register_valve_proxy_class_for(self.class, build_proxy_class)

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
