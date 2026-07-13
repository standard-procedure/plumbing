# frozen_string_literal: true

module Plumbing
  module Actor
    class Message < Literal::Struct
      include Plumbing::Awaitable

      prop :actor, Actor, writer: false
      prop :method, Symbol, writer: false
      prop :implementation, Symbol, writer: false, default: -> { :"_#{@method}" }
      prop :params, Hash, writer: false
      prop :block, _Callable?, writer: false
      prop :result, _Any?, reader: :public, writer: false
      prop :exception, _Nilable(Exception), reader: :public, writer: false
      prop :status, Plumbing.OneOf(:waiting, :done, :error), default: :waiting, reader: :public, writer: false

      def deliver
        @result = @actor.send(@implementation, **@params, &@block)
        @status = :done
      rescue => ex
        @exception = ex
        @status = :error
      end

      def await
        _wait_until_ready
        @exception.nil? ? @result : raise(@exception)
      end

      def _wait_until_ready
        raise NotImplementedError
      end
    end
  end
end
