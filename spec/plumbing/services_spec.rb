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

  describe "provide (factory)" do
    it "builds a fresh object on every access" do
      services.provide(:clock) { Object.new }
      expect(services[:clock]).not_to be(services[:clock])
    end

    it "requires a block" do
      expect { services.provide(:x) }.to raise_error(ArgumentError)
    end
  end

  describe "aliases" do
    it "exposes singleton -> register and factory -> provide" do
      expect(services.method(:singleton).original_name).to eq(:register)
      expect(services.method(:factory).original_name).to eq(:provide)
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

  describe "parameterised routes" do
    it "binds path parameters to block keywords" do
      services.provide("people/:id/addresses") { |id:| ["address-for-#{id}"] }
      expect(services["/people/123/addresses"]).to eq(["address-for-123"])
    end

    it "passes parameter values as strings" do
      services.provide("widgets/:id") { |id:| id }
      expect(services["/widgets/42"]).to eq("42")
    end

    it "binds multiple parameters by name, independent of order" do
      services.provide("orgs/:org_id/people/:id") { |id:, org_id:| "#{org_id}-#{id}" }
      expect(services["/orgs/7/people/9"]).to eq("7-9")
    end

    it "treats leading and trailing slashes as optional" do
      services.provide("widgets/:id") { |id:| id }
      expect(services["widgets/5"]).to eq("5")
      expect(services["/widgets/5/"]).to eq("5")
    end

    it "raises KeyError when no route matches" do
      services.provide("people/:id") { |id:| id }
      expect { services["/widgets/1"] }.to raise_error(KeyError)
    end

    it "raises KeyError when the path has the wrong number of segments" do
      services.provide("people/:id") { |id:| id }
      expect { services["/people/1/extra"] }.to raise_error(KeyError)
    end
  end

  describe "provide on a route (fresh each access)" do
    it "re-runs the block on every access" do
      calls = 0
      services.provide("people/:id") do |id:|
        calls += 1
        Object.new
      end
      a = services["/people/1"]
      b = services["/people/1"]
      expect(a).not_to be(b)
      expect(calls).to eq(2)
    end
  end

  describe "register on a route (singleton per concrete path)" do
    it "caches one instance per distinct path" do
      calls = 0
      services.register("people/:id") do |id:|
        calls += 1
        Object.new
      end
      a = services["/people/1"]
      b = services["/people/1"]
      c = services["/people/2"]
      expect(a).to be(b)
      expect(a).not_to be(c)
      expect(calls).to eq(2)
    end
  end

  describe "route precedence" do
    it "prefers a static segment over a parameter, regardless of registration order" do
      services.register("people/:id") { |id:| "dynamic-#{id}" }
      services.register("people/me") { "static-me" }
      expect(services["/people/me"]).to eq("static-me")
      expect(services["/people/42"]).to eq("dynamic-42")
    end
  end
end
