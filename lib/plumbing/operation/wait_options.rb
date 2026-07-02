# frozen_string_literal: true

module Plumbing
  module Operations
    # Poll/timeout configuration for a wait state. Durations are seconds;
    # the DSL coerces values via to_f. Consumed by Plan 2b.
    class WaitOptions < Literal::Data
      prop :delay, _Float, default: 10.0
      prop :timeout, _Float, default: 86_400.0
    end
  end
end
