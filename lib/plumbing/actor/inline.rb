# frozen_string_literal: true

require_relative "worker"

module Plumbing
  module Actor
    class Inline < Worker
      def call = nil
      def stop = nil

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
