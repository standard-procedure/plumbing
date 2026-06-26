# frozen_string_literal: true

require_relative "message"

module Plumbing
  module Actor
    class Worker < Literal::Data
      prop :actor, Plumbing::Actor

      def call = raise NotImplementedError
      alias_method :start, :call

      def stop = raise NotImplementedError

      def active? = raise NotImplementedError

      def post method, sender: nil, **params, &block
        build_message(method: method, sender: sender, params: params, block: block).tap do |message|
          dispatch message
        end
      end

      def build_message(method:, sender:, params:, block:) = message_class.new(actor: @actor, method:, sender:, params:, block:)

      def message_class = Plumbing::Actor::Message

      def dispatch(message) = raise NotImplementedError
    end
  end
end
