# frozen_string_literal: true

module Plumbing
  module Actor
    module Configuration
      def worker_for actor
        worker_types[selected_worker_type].call(actor)
      end

      def uses name
        @selected_worker_type = name.to_sym
      end

      def selected_worker_type
        @selected_worker_type ||= :inline
      end

      def workers = worker_types.keys

      def register name, &builder
        worker_types[name.to_sym] = builder
      end

      def worker_types
        @worker_types ||= {inline: ->(actor) { Plumbing::Actor::Inline.new(actor: actor) }}
      end
    end
  end
end
