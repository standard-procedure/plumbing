# frozen_string_literal: true

module Plumbing
  class Provider
    require_relative "provider/router"

    include Literal::Types

    def initialize
      @values = {}
      @router = Router.new
      @lock = Mutex.new
    end

    def register path, value = nil, &provider
      raise ArgumentError unless value.nil? ^ provider.nil?
      safely do
        route = @router.register path
        raise ArgumentError if !value.nil? && route.dynamic?
        value.nil? ? _register_dynamic(route.path, provider) : _set(route.path, value)
      end
    end
    alias_method :singleton, :register

    def provide path, &provider
      safely do
        route = @router.register path
        _set_dynamic(route.path, provider)
      end
    end
    alias_method :factory, :provide

    def get path
      query = @router.query path
      _value_for(query).get(query)
    end
    alias_method :[], :get

    def safely(&) = @lock.synchronize(&)

    private def _set(path, value)
      @values[path] = StaticValue.new value:
    end

    private def _register_dynamic(path, provider)
      cache_updater = ->(query, value) do
        safely { _set(query.path, value) }
      end
      @values[path] = SelfCachingValue.new provider:, cache_updater:
    end

    private def _set_dynamic(path, provider)
      @values[path] = DynamicValue.new provider:
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
  end

  def self.services
    @services ||= Provider.new
  end
end
