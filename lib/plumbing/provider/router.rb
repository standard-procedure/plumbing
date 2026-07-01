# frozen_string_literal: true

module Plumbing
  class Provider
    class Router
      class Route < Literal::Data
        prop :path, String
      end

      class StaticRoute < Route
        def static? = true
        def dynamic? = false
        def params = {}.freeze
      end

      class DynamicRoute < Route
        prop :segments, _Array(String), default: -> { @path.split("/") }
        prop :params, _Hash(_Integer, Symbol), default: -> { _generate_params }
        prop :statics, _Hash(_Integer, String), default: -> { _generate_statics }
        prop :params_count, _Integer, default: -> { @params.keys.count }
        def static? = false
        def dynamic? = true

        def matches_for path
          segments = path.split("/")
          _match_for?(segments) ? @statics.size : 0
        end

        def _generate_params
          @path.split("/")
            .map
            .with_index { |segment, position| [position, segment] }
            .select { |(position, segment)| segment.start_with? ":" }
            .map { |(position, segment)| [position, segment.delete_prefix(":").to_sym] }
            .to_h
        end

        def _generate_statics
          @path.split("/")
            .map
            .with_index { |segment, position| [position, segment] }
            .reject { |(position, segment)| segment.start_with? ":" }
            .to_h
        end

        def _match_for?(segments) = _size_match_for?(segments) && _static_match_for?(segments)
        def _size_match_for?(segments) = (segments.size == @segments.size)

        def _static_match_for?(segments) = @statics.all? { |position, segment| segments[position] == segment }
      end

      class Query < Literal::Data
        prop :route, Route
        prop :path, String
        prop :key, String, default: -> { @route.path }
        prop :segments, _Array(String), default: -> { @path.split("/") }
        prop :params, _Hash(Symbol, _Any), default: -> { _generate_params }

        private def _generate_params
          @route.params.keys.each_with_object({}) do |position, result|
            result[@route.params[position]] = @segments[position]
          end
        end
      end

      def initialize
        @static_routes = {}
        @dynamic_routes = Set.new
      end

      def register path
        path = _clean path
        dynamic?(path) ? _register_dynamic(path) : _register_static(path)
      end

      def query path
        path = _clean path
        route = _static_route_for(path) || _dynamic_route_for(path)

        raise InvalidPath.new(path) if route.nil?
        Query.new(route: route, path: path)
      end

      def dynamic?(path) = path.include?(":")

      private def _clean(path) = path.to_s.delete_prefix("/").delete_suffix("/")

      private def _register_static path
        StaticRoute.new(path: path).tap do |route|
          @static_routes[route.path] = route
        end
      end

      private def _register_dynamic path
        DynamicRoute.new(path: path).tap do |route|
          @dynamic_routes << route
        end
      end
      private def _static_route_for(path) = @static_routes[_clean(path)]
      private def _dynamic_route_for(path) = _matches_for(path).reject(&:none?).max_by(&:count)&.route
      private def _matches_for(path) = @dynamic_routes.map { |route| RouteMatch.new(route: route, count: route.matches_for(path)) }

      class RouteMatch < Literal::Data
        prop :route, Route
        prop :count, _Integer
        def none? = @count == 0
      end
      private_constant :RouteMatch

      class InvalidPath < StandardError
      end
    end
  end
end
