# frozen_string_literal: true

module Plumbing
  # A lock-free service locator that doubles as a path router. Flat keys are
  # prefilled at startup and read synchronously; the registry is assumed
  # immutable once the app has booted.
  #
  #   Plumbing.services.register :config, AppConfig.load   # eager singleton
  #   Plumbing.services.register(:db) { Database.connect } # lazy singleton
  #   Plumbing.services.provide(:clock) { Time.now }       # fresh every access
  #   Plumbing.services[:db]
  #
  # Names containing "/" are routes. Static segments match literally; ":name"
  # segments capture a value bound to the block's keyword of the same name:
  #
  #   services.provide("people/:id/addresses") { |id:| Person.find(id).addresses }
  #   services["/people/123/addresses"]   # => the addresses, recomputed each call
  #
  #   services.register("people/:id") { |id:| PersonActor.spawn(id) }
  #   services["/people/123"]             # => one cached actor per concrete path
  #
  # A static segment is preferred over a parameter at the same position, so
  # "people/me" wins over "people/:id" regardless of registration order.
  #
  # Routes registered with +register+ cache one instance per concrete path.
  # That cache is the only structure written at read time, so it is guarded by
  # a mutex; every other read remains lock-free.
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

    # A registered path pattern. +segments+ is an array of {static:} / {param:}
    # hashes; +mode+ is :singleton or :factory.
    Route = Struct.new(:segments, :mode, :builder, :object) do
      def static_count
        segments.count { |segment| segment.key?(:static) }
      end

      # Returns a params hash if +query+ (an array of path segments) matches,
      # otherwise nil.
      def match(query)
        return nil unless query.length == segments.length
        params = {}
        segments.each_with_index do |segment, i|
          if segment.key?(:static)
            return nil unless segment[:static] == query[i]
          else
            params[segment[:param]] = query[i]
          end
        end
        params
      end
    end
    private_constant :Route

    def initialize
      @entries = {}
      @routes = []
      @cache = {}
      @mutex = Mutex.new
    end

    # Always returns the same object. Eager when given +object+, lazy (built
    # once on first access) when given a block. On a parameterised route, the
    # block is built once per concrete path and cached. Alias: +singleton+.
    def register(name, object = nil, &builder)
      raise ArgumentError, "supply exactly one of object/builder" unless object.nil? ^ builder.nil?
      if route?(name)
        @routes << Route.new(compile(name), :singleton, builder, object)
      else
        @entries[name.to_sym] = object.nil? ? Singleton.new(builder, nil, false) : Singleton.new(nil, object, true)
      end
      name
    end
    alias_method :singleton, :register

    # Builds a fresh object on every access. Alias: +factory+.
    def provide(name, &builder)
      raise ArgumentError, "provide requires a block" if builder.nil?
      if route?(name)
        @routes << Route.new(compile(name), :factory, builder, nil)
      else
        @entries[name.to_sym] = builder
      end
      name
    end
    alias_method :factory, :provide

    # Resolve a service by name or path. Raises KeyError if nothing matches.
    def [](query)
      segments = normalize(query)
      if segments.length == 1 && @entries.key?(segments.first.to_sym)
        return resolve_entry(@entries[segments.first.to_sym])
      end
      route, params = best_match(segments)
      raise KeyError, "no service registered for #{query.inspect}" if route.nil?
      resolve_route(route, params, segments)
    end

    private

    def route?(name)
      name.to_s.include?("/")
    end

    def compile(name)
      normalize(name).map do |segment|
        segment.start_with?(":") ? {param: segment[1..].to_sym} : {static: segment}
      end
    end

    def normalize(query)
      query.to_s.delete_prefix("/").delete_suffix("/").split("/")
    end

    def resolve_entry(entry)
      entry.is_a?(Singleton) ? entry.resolve : entry.call
    end

    # The most-static matching route wins; ties resolve to the earliest
    # registration.
    def best_match(segments)
      best = nil
      best_params = nil
      @routes.each do |route|
        params = route.match(segments)
        next if params.nil?
        if best.nil? || route.static_count > best.static_count
          best = route
          best_params = params
        end
      end
      [best, best_params]
    end

    def resolve_route(route, params, segments)
      return route.object unless route.object.nil?
      return route.builder.call(**params) if route.mode == :factory

      key = segments.join("/")
      @mutex.synchronize do
        @cache.key?(key) ? @cache[key] : (@cache[key] = route.builder.call(**params))
      end
    end
  end

  # The shared default registry.
  def self.services
    @services ||= Services.new
  end
end
