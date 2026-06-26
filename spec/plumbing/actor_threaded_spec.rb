# frozen_string_literal: true

require "plumbing/actor/threaded"

RSpec.describe Plumbing::Actor::Threaded do
  before { Plumbing::Actor.uses :threaded }
  after { Plumbing::Actor.uses :inline }

  let(:greeter) do
    Class.new do
      include Plumbing::Actor
      async :greet do
        param :name, String
        returns { |name:| "Hello #{name}" }
      end
    end
  end

  it "produces actors backed by a Threaded worker" do
    expect(greeter.new.worker).to be_a(Plumbing::Actor::Threaded)
  end

  it "returns a Threaded::Message" do
    expect(greeter.new.greet(name: "X")).to be_a(Plumbing::Actor::Threaded::Message)
  end

  it "delivers and returns the result via await" do
    expect(greeter.new.greet(name: "Cher").await).to eq "Hello Cher"
  end

  it "delivers on a thread other than the caller's" do
    catcher = Class.new do
      include Plumbing::Actor
      async(:where) { returns { Thread.current.object_id } }
    end.new
    expect(catcher.where.await).not_to eq(Thread.current.object_id)
  end

  it "processes one actor's messages sequentially, in arrival order" do
    recorder = Class.new do
      include Plumbing::Actor
      def initialize = (super; @order = [])
      async :record do
        param :n, Integer
        returns { |n:| @order << n }
      end
      async(:order) { returns { @order.dup } }
    end.new
    (1..50).map { |n| recorder.record(n: n) }.each(&:await)
    expect(recorder.order.await).to eq((1..50).to_a)
  end

  it "propagates exceptions through await" do
    boom = Class.new do
      include Plumbing::Actor
      async(:explode) { returns { raise "boom" } }
    end.new
    expect { boom.explode.await }.to raise_error(RuntimeError, "boom")
  end

  it "tracks current_sender across the thread boundary" do
    inner = Class.new do
      include Plumbing::Actor
      async(:who) { returns { current_sender } }
    end.new
    sender = greeter.new
    expect(inner.who(sender: sender).await).to be(sender)
  end
end
