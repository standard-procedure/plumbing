# frozen_string_literal: true

require_relative "actor/configuration"
require_relative "actor/definitions"
require_relative "actor/properties"
require_relative "actor/observable"
require_relative "actor/inline"

module Plumbing
  module Actor
    extend Configuration

    FIBER_KEY = :plumbing_actor_sender_stack

    # Raised when an actor asks for a capability its worker cannot provide
    # (e.g. deferring a message on the inline worker).
    NotSupported = Class.new(StandardError)

    # Ask the worker to deliver `call` to this actor after `delay` seconds.
    # Returns a Plumbing::Actor::Deferral that can be passed to cancel_deferred.
    def after(delay, call:, sender: nil, **params, &block)
      @worker.after(delay, method: call, params: params, block: block)
    end

    # Cancel a deferral returned by #after.
    def cancel_deferred(deferral) = @worker.cancel_deferred(deferral)

    def start
      before_start
      @worker.start
      after_start
    end
    alias_method :call, :start

    def stop
      before_stop
      @worker.stop
      after_stop
    end

    def active? = @worker.active?

    private def before_start = nil
    private def after_start = nil
    private def before_stop = nil
    private def after_stop = nil
    private def current_sender = @current_sender

    module Start
      def start(**) = new(**).tap { |a| a.start }
      def call(**) = start(**)
    end

    def self.included klass
      klass.extend Literal::Properties
      klass.extend Definitions
      klass.extend Properties
      klass.extend Start

      klass.prop :worker, Plumbing::Actor::Worker, default: -> { Plumbing::Actor.worker_for self }, reader: :public, writer: false
      klass.prop :current_sender, Literal::Types._Nilable(Plumbing::Actor), default: nil
    end
  end
end
