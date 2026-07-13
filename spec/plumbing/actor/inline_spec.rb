# frozen_string_literal: true

require_relative "worker"

RSpec.describe Plumbing::Actor::Inline do
  # `:inline` is the default worker; reset explicitly in case a prior spec
  # has left the registry pointing somewhere else.
  before { Plumbing::Actor.uses :inline }

  it_behaves_like "a worker"
end
