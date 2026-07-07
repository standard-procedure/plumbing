# frozen_string_literal: true

RSpec.describe Plumbing::Provider do
  subject(:provider) { described_class.new }

  describe "register (singleton)" do
    it "rejects ambiguous registrations" do
      expect { provider.register("object").await }.to raise_error ArgumentError
      expect { provider.register("object", "Object") { "Dynamic" }.await }.to raise_error ArgumentError
    end

    context "given a static path" do
      it "registers and returns a static object as-is" do
        object = Object.new

        provider.register path: "a/path", value: object

        expect(provider["a/path"].object_id).to eq object.object_id
      end

      it "registers and returns an on-demand object" do
        object = Object.new

        provider.register(path: "a/path") { object }

        expect(provider["a/path"].object_id).to eq object.object_id
      end

      it "returns the same on-demand object on subsequent requests" do
        provider.register(path: "a/path") { Object.new }

        first = provider["a/path"]
        second = provider["a/path"]

        expect(first.object_id).to eq second.object_id
      end

      it "does not build the on-demand object before it is requested" do
        built = nil

        provider.register(path: "a/path") { built = Object.new }

        expect(built).to eq nil
        found = provider["a/path"]
        expect(found.object_id).to eq built.object_id
      end

      it "raises an error if given an invalid path" do
        provider.register path: "a", value: "aardvark"
        provider.register(path: "b") { "badger" }

        expect { provider["c"] }.to raise_error Plumbing::Provider::Router::InvalidPath
      end
    end

    context "given a dynamic path" do
      it "does not allow a static object to be registered" do
        expect { provider.register(path: "locate/:object", value: "object").await }.to raise_error ArgumentError
      end

      it "registers and returns an on-demand object based upon the parameters provided" do
        provider.register path: "returns/:number" do |number:|
          number.to_i
        end

        expect(provider["returns/123"]).to eq 123
      end

      it "returns the same on-demand object on subsequent requests given the same parameters" do
        provider.register path: "say/:something" do |something:|
          something.to_s.reverse
        end

        first = provider["say/hello"]
        second = provider["say/hello"]

        expect(first.object_id).to eq second.object_id
      end

      it "returns a different on-demand object on subsequent requests given different parameters" do
        provider.register path: "say/:something" do |something:|
          something.to_s.reverse
        end

        first = provider["say/hello"]
        second = provider["say/goodbye"]

        expect(first.object_id).to_not eq second.object_id
      end

      it "raises an error if given an invalid path" do
        provider.register path: "say/:something" do |something:|
          something.to_s.reverse
        end

        expect { provider["shout/hello"] }.to raise_error Plumbing::Provider::Router::InvalidPath
      end
    end
  end

  describe "provide (factory)" do
    context "given a static path" do
      it "registers and returns an object on-demand" do
        object = Object.new

        provider.provide(path: "a/path") { object }

        expect(provider["a/path"].object_id).to eq object.object_id
      end

      it "creates a new object on subsequent requests" do
        provider.provide(path: "a/path") { Object.new }

        first = provider["a/path"]
        second = provider["a/path"]

        expect(first.object_id).to_not eq second.object_id
      end

      it "does not build the on-demand object before it is requested" do
        built = nil

        provider.provide(path: "a/path") { built = Object.new }

        expect(built).to eq nil
        found = provider["a/path"]
        expect(found.object_id).to eq built.object_id
      end

      it "raises an error if given an invalid path" do
        provider.provide(path: "a") { "aardvark" }

        expect { provider["c"] }.to raise_error Plumbing::Provider::Router::InvalidPath
      end
    end

    context "given a dynamic path" do
      it "registers and returns an object on-demand based upon the parameters provided" do
        provider.provide path: "greet/:name/with/:greeting" do |name:, greeting:|
          "#{greeting.capitalize} #{name.capitalize}"
        end

        expect(provider["greet/alice/with/hello"]).to eq "Hello Alice"
      end

      it "creates a new object on subsequent requests given the same parameters" do
        provider.provide path: "greet/:name/with/:greeting" do |name:, greeting:|
          "#{greeting} #{name}"
        end

        first = provider["greet/alice/with/hello"]
        second = provider["greet/alice/with/hello"]

        expect(first.object_id).to_not eq second.object_id
      end

      it "does not build the on-demand object before it is requested" do
        built = nil

        provider.provide path: "say/:something" do |something:|
          built = something.to_s
        end

        expect(built).to eq nil
        found = provider["say/hello"]
        expect(found.object_id).to eq built.object_id
      end

      it "raises an error if given an invalid path" do
        provider.provide path: "say/:something" do |something:|
          something.to_s.reverse
        end

        expect { provider["shout/hello"] }.to raise_error Plumbing::Provider::Router::InvalidPath
      end
    end
  end

  describe "aliases" do
    it "exposes singleton -> register and factory -> provide" do
      expect(provider.method(:singleton).original_name).to eq(:register)
      expect(provider.method(:factory).original_name).to eq(:provide)
    end
  end

  describe "Plumbing.services" do
    it "is a shared, memoized default registry" do
      expect(Plumbing.services).to be_a(described_class)
      expect(Plumbing.services).to be(Plumbing.services)
    end
  end
end
