# frozen_string_literal: true

module Plumbing
  module Actor
    module Observable
      def add_observer(&observer) = @pipeline.add_observer(&observer)
      def remove_observer(observer:) = @pipeline.remove_observer(observer: observer)
      def remove_all_observers = @pipeline.remove_all_observers

      private def push(event:, debounce: true) = @pipeline.push(event:, debounce:)
      private def notify(event_type, debounce: true, source: nil, **params) = @pipeline.notify(event_type, debounce: true, source: self, **params)

      def self.included klass
        klass.extend Literal::Properties
        klass.prop :pipeline, Plumbing::Pipeline, default: -> { Plumbing::Pipeline.new }
      end
    end
  end
end
