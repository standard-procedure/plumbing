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
        if route.wildcard?
          _register_wildcard(route.path, value, provider)
        elsif value.nil?
          _register_dynamic(route.path, provider, expires_in)
        else
          raise ArgumentError if route.dynamic?
          _set(route.path, value)
        end
      end
    end
    alias_method :singleton, :register

    async :provide do
      param :path, String

      returns do |path:, &provider|
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
    # block is checked when it resolves (see DynamicWildcard).
    private def _register_wildcard(path, value, provider)
      if value.nil?
        @values[path] = DynamicWildcard.new provider:
      else
        raise ArgumentError unless value.is_a?(Plumbing::Provider)
        @values[path] = StaticWildcard.new nested: value
      end
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
    # block. Because the block's result is only known when it runs, the
    # Provider constraint is enforced here rather than at registration.
    class DynamicWildcard < Literal::Data
      prop :provider, _Callable
      def get(query)
        nested = @provider.call
        raise ArgumentError unless nested.is_a?(Plumbing::Provider)
        query.remainder.empty? ? nested : nested[query.remainder]
      end
    end
    private_constant :DynamicWildcard
  end

  def self.services
    @services ||= Provider.new
  end
end
