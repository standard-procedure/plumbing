# frozen_string_literal: true

module Plumbing
  class Operation
    Error = Class.new(StandardError)
    NoDecision = Class.new(Error)     # a decision matched no condition
    NoTransition = Class.new(Error)   # an action has no `.then`
    Timeout = Class.new(Error)        # a wait exceeded its timeout (Plan 2b)
    InvalidState = Class.new(Error)   # an interaction called in the wrong state (Plan 2b)
  end
end
