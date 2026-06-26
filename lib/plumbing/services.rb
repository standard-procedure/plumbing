# frozen_string_literal: true

module Plumbing
  # A lock-free service locator, prefilled at startup. Reads are synchronous;
  # the registry is assumed immutable once the app has booted. (A future
  # actor-based variant can support clients dropping on/off dynamically.)
  #
  #   Plumbing.services.register :config, AppConfig.load   # eager singleton
  #   Plumbing.services.register(:db) { Database.connect } # lazy singleton
  #   Plumbing.services.create(:clock) { Time.now }        # fresh every access
  #   Plumbing.services[:db]
  class Services
    Singleton = Struct.new(:builder, :value, :built) do
      def resolve
        return value if built
        self.value = builder.call
        self.built = true
        value
      end
    end
    private_constant :Singleton

    def initialize
      @entries = {}
    end

    # Always returns the same object. Eager when given `object`, lazy (built
    # once on first access) when given a block. Alias: +singleton+.
    def register(name, object = nil, &builder)
      raise ArgumentError, "supply exactly one of object/builder" unless object.nil? ^ builder.nil?
      @entries[name.to_sym] = object.nil? ? Singleton.new(builder, nil, false) : Singleton.new(nil, object, true)
      name.to_sym
    end
    alias_method :singleton, :register

    # Builds a fresh object on every access. Alias: +factory+.
    def create(name, &builder)
      raise ArgumentError, "create requires a block" if builder.nil?
      @entries[name.to_sym] = builder
      name.to_sym
    end
    alias_method :factory, :create

    # Resolve a service by name. Raises KeyError if it is not registered.
    def [](name)
      entry = @entries.fetch(name.to_sym)
      entry.is_a?(Singleton) ? entry.resolve : entry.call
    end
  end

  # The shared default registry.
  def self.services
    @services ||= Services.new
  end
end
