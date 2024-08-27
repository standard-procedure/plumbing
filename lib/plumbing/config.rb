module Plumbing
  Config = Data.define :mode, :valve_proxy_classes, :async_limit, :timeout do
    def valve_proxy_class_for target_class
      valve_proxy_classes[target_class]
    end

    def register_valve_proxy_class_for target_class, proxy_class
      valve_proxy_classes[target_class] = proxy_class
    end
  end

  def self.config
    configs.last
  end

  def self.configure(**params, &block)
    new_config = Config.new(**config.to_h.merge(params).merge(valve_proxy_classes: {}))
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
    @configs ||= [Config.new(mode: :inline, async_limit: 8, timeout: 30, valve_proxy_classes: {})]
  end
  private_class_method :configs
end
