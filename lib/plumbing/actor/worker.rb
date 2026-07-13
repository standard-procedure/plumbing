# frozen_string_literal: true

require_relative "message"
require_relative "deferral"

module Plumbing
  module Actor
    class Worker < Literal::Data
      prop :actor, Plumbing::Actor

      def start = raise NotImplementedError
      def call = start

      def stop = raise NotImplementedError

      def active? = raise NotImplementedError

      def post method, **params, &block
        build_message(method: method, params: params, block: block).tap do |message|
          dispatch message
        end
      end

      def can_defer? = false

      # Deliver `methodfalse
      # handle. Base raises; each worker implements its own timer.
      def after(delay, method:, params: {}, block: nil) = raise NotImplementedError

      # Cancel a previously-scheduled deferral (race-safe no-op flag).
      def cancel_deferred(deferral) = deferral&.cancel

      def build_message(method:, params:, block:) = message_class.new(actor: @actor, method:, params:, block:)

      def message_class = Plumbing::Actor::Message

      def dispatch(message) = raise NotImplementedError
    end
  end
end
