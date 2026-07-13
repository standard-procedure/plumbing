# frozen_string_literal: true

require "plumbing/actor/threaded"
require_relative "worker"
require_relative "deferred_worker"

RSpec.describe Plumbing::Actor::Threaded do
  before { Plumbing::Actor.uses :threaded }
  after { Plumbing::Actor.uses :inline }

  it_behaves_like "a worker"
  it_behaves_like "a deferred worker"
end
