# frozen_string_literal: true

require_relative "../provider"

module Plumbing
  class Event
    class Types
      def initialize
        @provider = Provider.new
      end

      def register klass, name: nil
        name ||= klass.name
        await { @provider.register path: name, value: klass }
        klass
      end

      def build event_type, source: nil, **params
        @provider[event_type].new source: source, **params
      end

      def remove_all
        # TODO: await { @provider.remove_all }
      end
    end
  end
end
