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
        calls { |name:| "Hello #{name}" }
      end
    end
  end

  it "produces actors backed by a Threaded worker" do
    expect(greeter.new.worker).to be_a(Plumbing::Actor::Threaded)
  end

  it "calls a Threaded::Message" do
    expect(greeter.new.greet(name: "X")).to be_a(Plumbing::Actor::Threaded::Message)
  end

  it "delivers and calls the result via await" do
    expect(greeter.new.greet(name: "Cher").await).to eq "Hello Cher"
  end

  it "delivers on a thread other than the caller's" do
    catcher = Class.new do
      include Plumbing::Actor

      async(:where) { calls { Thread.current.object_id } }
    end.new
    expect(catcher.where.await).not_to eq(Thread.current.object_id)
  end

  it "processes one actor's messages sequentially, in arrival order" do
    recorder = Class.new do
      include Plumbing::Actor

      def initialize
        super
        @order = []
      end

      async :record do
        param :n, Integer
        calls { |n:| @order << n }
      end
      async(:order) { calls { @order.dup } }
    end.new
    (1..50).map { |n| recorder.record(n: n) }.each(&:await)
    expect(recorder.order.await).to eq((1..50).to_a)
  end

  it "propagates exceptions through await" do
    boom = Class.new do
      include Plumbing::Actor

      async(:explode) { calls { raise "boom" } }
    end.new
    expect { boom.explode.await }.to raise_error(RuntimeError, "boom")
  end

  it "tracks current_sender across the thread boundary" do
    inner = Class.new do
      include Plumbing::Actor

      async(:who) { calls { current_sender } }
    end.new
    sender = greeter.new
    expect(inner.who(sender: sender).await).to be(sender)
  end

  it "stops its worker when sent #stop" do
    actor = greeter.new
    expect(actor.worker).to be_active

    actor.stop

    expect(actor.worker).not_to be_active
  end
end
