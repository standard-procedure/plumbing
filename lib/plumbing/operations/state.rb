# frozen_string_literal: true

require_relative "transition"
require_relative "wait_options"

module Plumbing
  module Operations
    # A node in the state machine. `action` runs on entry (nil for
    # decision/result). `transitions` are ordered; the first matching guard
    # wins. `wait_options` is set only for :wait states (Plan 2b).
    class State < Literal::Data
      prop :name, Symbol
      prop :kind, Plumbing.OneOf(:action, :decision, :wait, :result)
      prop :action, _Callable?
      prop :transitions, _Array(Transition), default: [].freeze
      prop :wait_options, _Nilable(WaitOptions)
    end
  end
end
