# frozen_string_literal: true

module Plumbing
  class Provider
    include Literal::Types
    include Plumbing::Actor

    require_relative "provider/router"

    def initialize
      super
      @values = {}
      @router = Router.new
      @lock = Mutex.new
    end

    async :register do
      param :path, String
      param :value, _Any?, default: nil
      param :expires_in, _Nilable(Numeric), default: nil

      returns do |path:, value:, expires_in:, &provider|
        raise ArgumentError unless value.nil? ^ provider.nil?
        route = @router.register path
        raise ArgumentError if value && route.has_params? # routes with parameters must use a block for registration
        if route.wildcard?
          _register_wildcard(route.path, value, provider, expires_in)
        elsif value.nil?
          _register_dynamic(route.path, provider, expires_in)
        else
          _set(route.path, value)
        end
      end
    end
    alias_method :singleton, :register

    async :provide do
      param :path, String

      returns do |path:, &provider|
        raise ArgumentError if provider.nil? # must use a block for providing an object
        route = @router.register path
        _set_dynamic(route.path, provider)
      end
    end
    alias_method :factory, :provide

    async :get do
      param :path, String

      returns do |path:|
        query = @router.query path
        _value_for(query).get(query)
      end
    end

    def [](path) = get(path:).await

    private def _set(path, value)
      @values[path] = StaticValue.new value:
    end

    private def _register_dynamic(path, provider, expires_in = nil)
      cache_updater = ->(query, value) do
        displaced = @values[query.path]
        _set(query.path, value)
        _schedule_eviction(query.path, displaced, expires_in) if expires_in
      end
      @values[path] = SelfCachingValue.new provider:, cache_updater:
    end

    # Ask the worker to evict a cached value after `expires_in` seconds. The
    # :inline worker has no loop to deliver a later message and raises
    # NotSupported — in that case TTL degrades to cache-forever, the same way a
    # cache store with no expiry sweeper behaves.
    private def _schedule_eviction(path, displaced, expires_in)
      after(expires_in, call: :evict, path: path, restore: displaced)
    rescue Plumbing::Actor::NotSupported
      nil
    end

    # Delivered by the worker `expires_in` seconds after a value was cached, and
    # serialised with every other message. Restore the resolver that caching
    # displaced (a self-caching value, for a static singleton) so the next
    # lookup re-resolves; when nothing was displaced (a dynamic path, whose
    # resolver lives at the pattern key) just drop the concrete entry and let the
    # lookup fall through to re-resolve.
    private def _evict(path:, restore:)
      if restore.nil?
        @values.delete(path)
      else
        @values[path] = restore
      end
    end

    private def _set_dynamic(path, provider)
      @values[path] = DynamicValue.new provider:
    end

    # A wildcard registration ("some/path/*") mounts a nested Provider at the
    # prefix. Only Providers may be mounted: a static value is checked now; a
    # block is checked when it resolves (see CachingWildcard). A block form
    # caches the provider it builds (per parameter set), honouring `expires_in`.
    private def _register_wildcard(path, value, provider, expires_in)
      if value.nil?
        cache = {}
        on_cache = expires_in ? ->(params) { _schedule_wildcard_eviction(cache, params, expires_in) } : ->(_params) {}
        @values[path] = CachingWildcard.new(provider:, cache:, on_cache:)
      else
        raise ArgumentError unless value.is_a?(Plumbing::Provider)
        @values[path] = StaticWildcard.new nested: value
      end
    end

    # Schedule eviction of one cached parameter-set from a wildcard's cache. As
    # with singleton TTLs, the :inline worker can't defer, so TTL degrades to
    # cache-forever.
    private def _schedule_wildcard_eviction(cache, params, expires_in)
      after(expires_in, call: :evict_wildcard, cache: cache, key: params)
    rescue Plumbing::Actor::NotSupported
      nil
    end

    private def _evict_wildcard(cache:, key:)
      cache.delete(key)
    end

    private def _value_for(query)
      @values[query.path] || @values[query.key]
    end

    class StaticValue < Literal::Struct
      prop :value, _Any, writer: false
      def get(query) = @value
    end
    private_constant :StaticValue

    class DynamicValue < Literal::Data
      prop :provider, _Callable
      def get(query) = @provider.call(**query.params)
    end
    private_constant :DynamicValue

    class SelfCachingValue < Literal::Data
      prop :provider, _Callable
      prop :cache_updater, _Callable
      def get(query)
        @provider.call(**query.params).tap do |value|
          @cache_updater.call(query, value)
        end
      end
    end
    private_constant :SelfCachingValue

    # A nested Provider mounted at a wildcard prefix. A lookup of the bare
    # prefix returns the nested provider itself; a lookup with a tail delegates
    # the remaining path to it.
    class StaticWildcard < Literal::Data
      prop :nested, _Any
      def get(query) = query.remainder.empty? ? @nested : @nested[query.remainder]
    end
    private_constant :StaticWildcard

    # As StaticWildcard, but the nested Provider is produced on demand by a
    # block, which receives the prefix's captured params (so it can build a
    # provider scoped to them). Because this is `register`, the built provider is
    # cached — one per parameter set — and reused; `on_cache` lets the owning
    # Provider schedule TTL eviction for a freshly-cached entry. The Provider
    # constraint is enforced on build, since the block's result is only known
    # when it runs.
    #
    # `cache` is a mutable Hash held (not reassigned) by this frozen value; all
    # access is serialised by the owning Provider actor.
    class CachingWildcard < Literal::Data
      prop :provider, _Callable
      prop :cache, _Any, default: -> { {} }
      prop :on_cache, _Callable, default: -> { ->(_params) {} }

      def get(query)
        nested = _nested_for(query)
        query.remainder.empty? ? nested : nested[query.remainder]
      end

      def _nested_for(query)
        return @cache[query.params] if @cache.key?(query.params)
        @provider.call(**query.params).tap do |built|
          raise ArgumentError unless built.is_a?(Plumbing::Provider)
          @cache[query.params] = built
          @on_cache.call(query.params)
        end
      end
    end
    private_constant :CachingWildcard
  end

  def self.services
    @services ||= Provider.new
  end
end
