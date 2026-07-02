# frozen_string_literal: true

module Plumbing
  class Operation
    # One outgoing edge of a state. `guard` is a proc evaluated in the
    # operation's context; nil means unconditional (the "else" branch).
    # `label` is the human-readable mermaid edge text.
    class Transition < Literal::Data
      prop :target, Symbol
      prop :guard, _Callable?
      prop :label, _Nilable(String)

      def matches?(operation) = guard.nil? || operation.instance_exec(&guard)
    end
  end
end
