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

      returns do |path:, value:, &provider|
        raise ArgumentError unless value.nil? ^ provider.nil?
        route = @router.register path
        raise ArgumentError if !value.nil? && route.dynamic?
        value.nil? ? _register_dynamic(route.path, provider) : _set(route.path, value)
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

    private def _register_dynamic(path, provider)
      cache_updater = ->(query, value) do
        _set(query.path, value)
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
