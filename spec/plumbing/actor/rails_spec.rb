# frozen_string_literal: true

require "plumbing/actor/rails"
require_relative "worker"
require_relative "deferred_worker"

RSpec.describe Plumbing::Actor::Rails do
  # A fake Rails executor, so we can verify wrapping without booting a Rails app.
  let(:executor) do
    Class.new do
      attr_reader :wrapped
      def initialize = @wrapped = 0

      def wrap
        @wrapped += 1
        yield
      end
    end.new
  end

  before do
    app = Struct.new(:executor).new(executor)
    fake_rails = Module.new
    fake_rails.define_singleton_method(:application) { app }
    stub_const("Rails", fake_rails)
    Plumbing::Actor.uses :rails

  end

  after do
    Plumbing::Actor.uses :inline
  end

  it_behaves_like "a worker"
  it_behaves_like "a deferred worker"
end
