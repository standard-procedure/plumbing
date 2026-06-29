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
end
