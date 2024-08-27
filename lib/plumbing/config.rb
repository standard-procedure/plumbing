module Plumbing
  Config = Data.define :mode

  def self.config
    configs.last
  end

  def self.configure(**params, &block)
    new_config = Config.new(config.to_h.merge(params))
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
    @configs ||= [Config.new(:inline)]
  end
  private_class_method :configs
end
