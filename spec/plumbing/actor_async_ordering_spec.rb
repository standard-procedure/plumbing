# frozen_string_literal: true

require "plumbing/actor/async"
require "async"

# An actor MUST process its own messages one at a time, in arrival order.
# This is the defining guarantee of the actor model.
RSpec.describe "Plumbing::Actor::Async ordering" do
  before do
    Plumbing::Actor.register(:async) { |actor| Plumbing::Actor::Async.new(actor: actor) }
    Plumbing::Actor.uses :async
  end
  after do
    Plumbing::Actor.uses :inline
    Plumbing::Actor.worker_types.delete(:async)
  end

  let(:recorder) do
    Class.new do
      include Plumbing::Actor
      def initialize = (super; @order = [])
      async :record do
        param :n, Integer
        returns do |n:|
          # Later messages sleep LESS. If deliveries ran concurrently, a
          # later-but-faster message would record before an earlier-but-slower
          # one, scrambling the order. Sequential delivery keeps 1..10.
          sleep(0.05 - (n * 0.003))
          @order << n
        end
      end
      async(:order) { returns { @order.dup } }
    end
  end

  it "processes one actor's messages sequentially, in arrival order" do
    Sync do
      actor = recorder.new
      actor.worker.call
      msgs = (1..10).map { |n| actor.record(n: n) }
      msgs.each(&:await)
      expect(actor.order.await).to eq((1..10).to_a)
    end
  end
end
