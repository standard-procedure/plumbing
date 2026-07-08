# frozen_string_literal: true

module Plumbing
  module Actor
    module Configuration
      def worker_for actor
        worker_types[selected_worker_type][:builder].call(actor)
      end

      def can_defer? = worker_types[selected_worker_type][:can_defer]

      def uses name
        @selected_worker_type = name.to_sym
      end

      def selected_worker_type
        @selected_worker_type ||= :inline
      end

      def workers = worker_types.keys

      def register name, can_defer: false, &builder
        worker_types[name.to_sym] = {builder: builder, can_defer: can_defer}
      end

      def worker_types
        @worker_types ||= {inline: {builder: ->(actor) { Plumbing::Actor::Inline.new(actor: actor) }, can_defer: false}}
      end
    end
  end
end
