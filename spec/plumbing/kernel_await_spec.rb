# frozen_string_literal: true

RSpec.describe "Kernel#await / Kernel#Await" do
  describe "when the block result is Awaitable" do
    let(:awaitable) do
      Class.new do
        include Plumbing::Awaitable

        def initialize(value) = @value = value
        def await = "awaited:#{@value}"
      end
    end

    it "invokes .await and returns its result" do
      expect(await { awaitable.new("X") }).to eq "awaited:X"
    end

    it "works the same via the capitalised alias" do
      expect(Await { awaitable.new("Y") }).to eq "awaited:Y"
    end
  end

  describe "when the block result is not awaitable" do
    # An object is "awaitable" iff it includes Plumbing::Awaitable. The marker
    # module exists because `respond_to?(:await)` is unusable here — once
    # Kernel#await is defined, every Ruby object responds to :await.
    it "returns the block's value unchanged for strings" do
      expect(await { "plain" }).to eq "plain"
    end

    it "passes integers, hashes, and nil through" do
      expect(await { 42 }).to eq 42
      expect(await { {key: :value} }).to eq({key: :value})
      expect(await { nil }).to be_nil
    end

    it "does not call .await on objects that respond to it but aren't Awaitable" do
      not_really_awaitable = Class.new do
        def await = raise "should not be called"
      end.new
      expect(await { not_really_awaitable }).to be(not_really_awaitable)
    end
  end

  describe "exception propagation" do
    it "re-raises exceptions raised inside the block" do
      expect { await { raise "boom" } }.to raise_error(RuntimeError, "boom")
    end

    it "re-raises exceptions raised by the awaited result's .await" do
      raising = Class.new do
        include Plumbing::Awaitable

        def await = raise ArgumentError, "from await"
      end
      expect { await { raising.new } }.to raise_error(ArgumentError, "from await")
    end
  end

  describe "alias relationship" do
    it "exposes both lowercase await and capitalised Await" do
      expect(Kernel.instance_methods).to include(:await, :Await)
    end
  end
end
