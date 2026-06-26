# frozen_string_literal: true

RSpec.describe Plumbing::Services do
  subject(:services) { described_class.new }

  describe "register (singleton)" do
    it "returns an eagerly-registered object as-is" do
      obj = Object.new
      services.register(:thing, obj)
      expect(services[:thing]).to be(obj)
    end

    it "builds a lazy singleton once, on first access" do
      calls = 0
      services.register(:db) do
        calls += 1
        Object.new
      end
      a = services[:db]
      b = services[:db]
      expect(a).to be(b)
      expect(calls).to eq(1)
    end

    it "does not build a lazy singleton until accessed" do
      built = false
      services.register(:lazy) { built = true }
      expect(built).to be false
      services[:lazy]
      expect(built).to be true
    end

    it "rejects ambiguous or empty registration" do
      expect { services.register(:x, Object.new) { Object.new } }.to raise_error(ArgumentError)
      expect { services.register(:x) }.to raise_error(ArgumentError)
    end
  end

  describe "create (factory)" do
    it "builds a fresh object on every access" do
      services.create(:clock) { Object.new }
      expect(services[:clock]).not_to be(services[:clock])
    end

    it "requires a block" do
      expect { services.create(:x) }.to raise_error(ArgumentError)
    end
  end

  describe "aliases" do
    it "exposes singleton -> register and factory -> create" do
      expect(services.method(:singleton).original_name).to eq(:register)
      expect(services.method(:factory).original_name).to eq(:create)
    end
  end

  describe "lookup" do
    it "raises KeyError for an unknown service" do
      expect { services[:missing] }.to raise_error(KeyError)
    end

    it "accepts string or symbol names interchangeably" do
      obj = Object.new
      services.register("thing", obj)
      expect(services[:thing]).to be(obj)
    end
  end

  describe "Plumbing.services" do
    it "is a shared, memoized default registry" do
      expect(Plumbing.services).to be_a(described_class)
      expect(Plumbing.services).to be(Plumbing.services)
    end
  end
end
