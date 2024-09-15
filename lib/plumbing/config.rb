# Pipes, pipelines, actors and rubber ducks
module Plumbing
  Config = Data.define :mode, :actor_proxy_classes, :timeout do
    def actor_proxy_class_for target_class
      actor_proxy_classes[target_class]
    end

    def register_actor_proxy_class_for target_class, proxy_class
      actor_proxy_classes[target_class] = proxy_class
    end
  end
  private_constant :Config

  # Access the current configuration
  # @return [Config]
  def self.config
    configs.last
  end

  # Configure the plumbing
  # @param params [Hash] the configuration options
  # @option mode [Symbol] the mode to use (:inline is the default, :async uses fibers)
  # @option timeout [Integer] the timeout (in seconds) to use (30s is the default)
  # @yield optional block - after the block has completed its execution, the configuration is restored to its previous state (useful for test suites)
  def self.configure(**params, &block)
    new_config = Config.new(**config.to_h.merge(params).merge(actor_proxy_classes: {}))
    if block.nil?
      set_configuration_to new_config
    else
      set_configuration_and_yield new_config, &block
    end
  end

  def self.set_configuration_to config
    configs << config
  end
  private_class_method :set_configuration_to

  def self.set_configuration_and_yield(new_config, &block)
    set_configuration_to new_config
    yield
  ensure
    configs.pop
  end
  private_class_method :set_configuration_and_yield

  def self.configs
    @configs ||= [Config.new(mode: :inline, timeout: 30, actor_proxy_classes: {})]
  end
  private_class_method :configs
end
