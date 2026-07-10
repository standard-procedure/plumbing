# frozen_string_literal: true

require_relative "worker"

module Plumbing
  module Actor
    class Inline < Worker
      def start = nil
      def stop = nil

      def after(*, **) = raise Plumbing::Actor::NotSupported, "the inline worker cannot defer messages; use :async or :threaded"

      def dispatch message
        message.deliver
      end

      def message_class = Plumbing::Actor::Inline::Message

      class Message < Plumbing::Actor::Message
        def _wait_until_ready = nil
      end
    end
  end
end
