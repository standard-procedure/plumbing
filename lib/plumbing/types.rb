# frozen_string_literal: true

module Plumbing
  extend Literal::Types

  # Does the property value match one of the list of supplied values
  # USAGE:  `prop :enum, OneOf(:one, :two, :three)`
  def self.OneOf(*values) = proc { |v| values.include? v }

  # Does the property value match the signature for an Observable or a Pipeline?
  def self.Observable = _Interface(:add_observer, :remove_observer, :remove_all_observers)
  def self.Observable? = _Nilable(self.Observable)
end
