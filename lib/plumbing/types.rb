# frozen_string_literal: true

module Plumbing
  # A literal-compatible predicate matching any of the given values.
  # Primary use: as the type passed to a Literal prop (e.g. Message#status).
  def self.OneOf(*values) = proc { |v| values.include? v }

  # `Callable` already ships with literal as `Literal::Types._Callable` — use
  # that directly. `Observable` is the pipeline observer interface.
  Observable = Literal::Types._Interface(:observe, :remove, :remove_all)
end
