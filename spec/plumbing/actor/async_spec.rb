# frozen_string_literal: true

require "plumbing/actor/async"
require "async"
require_relative "worker"
require_relative "deferred_worker"

RSpec.describe Plumbing::Actor::Async do
  before do
    Plumbing::Actor.uses :async
  end

  around do |example|
    Sync(&example)
  end

  after do
    Plumbing::Actor.uses :inline
  end

  it_behaves_like "a worker"
  it_behaves_like "a deferred worker"
end
