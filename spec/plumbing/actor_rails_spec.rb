# frozen_string_literal: true

require "plumbing/actor/rails"

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

  it "produces actors backed by a Rails worker" do
    expect(greeter.new.worker).to be_a(Plumbing::Actor::Rails)
  end

  it "delivers and returns the result via await" do
    expect(greeter.new.greet(name: "Cher").await).to eq "Hello Cher"
  end

  it "wraps each delivery in the Rails executor" do
    actor = greeter.new
    actor.greet(name: "A").await
    actor.greet(name: "B").await
    expect(executor.wrapped).to eq 2
  end

  it "still processes one actor's messages sequentially, in order" do
    recorder = Class.new do
      include Plumbing::Actor

      def initialize
        super
        @order = []
      end

      async :record do
        param :n, Integer
        returns { |n:| @order << n }
      end
      async(:order) { returns { @order.dup } }
    end.new
    (1..20).map { |n| recorder.record(n: n) }.each(&:await)
    expect(recorder.order.await).to eq((1..20).to_a)
  end
end
