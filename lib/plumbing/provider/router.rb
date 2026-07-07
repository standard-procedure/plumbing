# frozen_string_literal: true

module Plumbing
  class Provider
    class Router
      class Route < Literal::Data
        prop :path, String
        def wildcard? = false
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

      # A wildcard route matches any query path that begins with its static
      # prefix segments; the tail (the "remainder") is handed to whatever the
      # provider resolves at the prefix — see Provider's wildcard delegation.
      # `path` here is the prefix, i.e. the registration path with its trailing
      # "/*" removed ("other/*" -> "other").
      class WildcardRoute < Route
        prop :segments, _Array(String), default: -> { @path.empty? ? [] : @path.split("/") }
        def static? = false
        def dynamic? = false
        def wildcard? = true
        def params = {}.freeze
        def prefix_size = @segments.size

        def matches?(path)
          query_segments = path.split("/")
          return false if query_segments.size < @segments.size
          @segments.each_with_index.all? { |segment, index| query_segments[index] == segment }
        end

        def remainder_for(path) = path.split("/").drop(@segments.size).join("/")
      end

      class Query < Literal::Data
        prop :route, Route
        prop :path, String
        prop :key, String, default: -> { @route.path }
        prop :segments, _Array(String), default: -> { @path.split("/") }
        prop :params, _Hash(Symbol, _Any), default: -> { _generate_params }
        prop :remainder, String, default: -> { @route.wildcard? ? @route.remainder_for(@path) : "" }

        private def _generate_params
          @route.params.keys.each_with_object({}) do |position, result|
            result[@route.params[position]] = @segments[position]
          end
        end
      end

      def initialize
        @static_routes = {}
        @dynamic_routes = Set.new
        @wildcard_routes = Set.new
      end

      def register path
        path = _clean path
        if wildcard?(path)
          _register_wildcard(path)
        elsif dynamic?(path)
          _register_dynamic(path)
        else
          _register_static(path)
        end
      end

      def query path
        path = _clean path
        route = _static_route_for(path) || _dynamic_route_for(path) || _wildcard_route_for(path)

        raise InvalidPath.new(path) if route.nil?
        Query.new(route: route, path: path)
      end

      def dynamic?(path) = path.include?(":")

      def wildcard?(path) = path.split("/").last == "*"

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

      private def _register_wildcard path
        prefix = path.split("/")[0...-1].join("/")
        WildcardRoute.new(path: prefix).tap do |route|
          @wildcard_routes << route
        end
      end
      private def _static_route_for(path) = @static_routes[_clean(path)]
      private def _dynamic_route_for(path) = _matches_for(path).reject(&:none?).max_by(&:count)&.route
      private def _matches_for(path) = @dynamic_routes.map { |route| RouteMatch.new(route: route, count: route.matches_for(path)) }
      # Longest matching prefix wins, so a more specific mount beats a shallower one.
      private def _wildcard_route_for(path) = @wildcard_routes.select { |route| route.matches?(path) }.max_by(&:prefix_size)

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
