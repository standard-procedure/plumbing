# frozen_string_literal: true

require "plumbing/actor/async"
require "plumbing/actor/threaded"
require "async"

RSpec.describe "Actor deferral" do
  describe Plumbing::Actor::Deferral do
    it "starts uncancelled and flips when cancelled" do
      deferral = described_class.new
      expect(deferral.cancelled?).to be false
      deferral.cancel
      expect(deferral.cancelled?).to be true
    end
  end

  describe "inline worker" do
    before { Plumbing::Actor.uses :inline }

    let(:actor_class) do
      Class.new do
        include Plumbing::Actor

        async(:noop) { returns { :ok } }
      end
    end

    it "raises NotSupported because there is no loop to deliver a later message" do
      actor = actor_class.new
      expect { actor.after(0.01, call: :noop) }.to raise_error(Plumbing::Actor::NotSupported)
    end
  end

  describe "async worker" do
    before do
      Plumbing::Actor.register(:async) { |actor| Plumbing::Actor::Async.new(actor: actor) }
      Plumbing::Actor.uses :async
    end
    after do
      Plumbing::Actor.uses :inline
      Plumbing::Actor.worker_types.delete(:async)
    end

    let(:counter_class) do
      Class.new do
        include Plumbing::Actor

        async(:tick) { returns { @count = (@count || 0) + 1 } }
        async(:count) { returns { @count || 0 } }
      end
    end

    it "delivers a deferred message after the delay" do
      Sync do |task|
        counter = counter_class.new
        counter.worker.call
        counter.after(0.05, call: :tick)
        task.sleep 0.15
        expect(counter.count.await).to eq 1
      end
    end

    it "does not deliver a cancelled deferred message" do
      Sync do |task|
        counter = counter_class.new
        counter.worker.call
        deferral = counter.after(0.05, call: :tick)
        counter.cancel_deferred(deferral)
        task.sleep 0.15
        expect(counter.count.await).to eq 0
      end
    end
  end

  describe "threaded worker" do
    before { Plumbing::Actor.uses :threaded }
    after { Plumbing::Actor.uses :inline }

    let(:counter_class) do
      Class.new do
        include Plumbing::Actor

        async(:tick) { returns { @count = (@count || 0) + 1 } }
        async(:count) { returns { @count || 0 } }
      end
    end

    it "delivers a deferred message after the delay" do
      counter = counter_class.new
      counter.after(0.05, call: :tick)
      sleep 0.2
      expect(counter.count.await).to eq 1
    end

    it "does not deliver a cancelled deferred message" do
      counter = counter_class.new
      deferral = counter.after(0.05, call: :tick)
      counter.cancel_deferred(deferral)
      sleep 0.2
      expect(counter.count.await).to eq 0
    end
  end
end
