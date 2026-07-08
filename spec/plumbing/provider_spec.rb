# frozen_string_literal: true

require "plumbing/actor/threaded"

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

    context "given a TTL" do
      context "with a worker that can defer (threaded)" do
        before { Plumbing::Actor.uses :threaded }
        after { Plumbing::Actor.uses :inline }

        it "evicts a cached singleton after expires_in and re-resolves on the next access" do
          count = 0
          provider.register(path: "counter", expires_in: 0.1) { count += 1 }

          expect(provider["counter"]).to eq 1   # resolved and cached
          expect(provider["counter"]).to eq 1   # served from cache, not re-resolved

          sleep 0.3                              # let the scheduled eviction fire

          expect(provider["counter"]).to eq 2   # cache evicted, resolver re-run
        end

        it "evicts a cached dynamic value after expires_in" do
          counts = Hash.new(0)
          provider.register(path: "count/:key", expires_in: 0.1) { |key:| counts[key] += 1 }

          expect(provider["count/a"]).to eq 1
          expect(provider["count/a"]).to eq 1

          sleep 0.3

          expect(provider["count/a"]).to eq 2
        end

        it "caches forever when no expires_in is given" do
          count = 0
          provider.register(path: "counter") { count += 1 }

          expect(provider["counter"]).to eq 1
          sleep 0.3
          expect(provider["counter"]).to eq 1
        end

        it "does not touch an evicted actor by default — the Provider does not own its lifecycle" do
          built = []
          provider.register(path: "svc", expires_in: 0.1) { Plumbing::Provider.new.tap { built << _1 } }

          provider["svc"]                       # resolve and cache the actor
          expect(built.size).to eq 1

          sleep 0.3                              # eviction fires

          expect(built.first.worker).to be_active # still running — not ours to stop
        end

        it "runs on_expiry: :stop against an evicted actor, releasing its worker" do
          built = []
          provider.register(path: "svc", expires_in: 0.1, on_expiry: :stop) { Plumbing::Provider.new.tap { built << _1 } }

          provider["svc"]
          expect(built.first.worker).to be_active

          sleep 0.3

          expect(built.first.worker).not_to be_active
        end

        it "runs a callable on_expiry with the evicted value" do
          torn_down = []
          value = Object.new
          provider.register(path: "svc", expires_in: 0.1, on_expiry: ->(object) { torn_down << object }) { value }

          provider["svc"]
          sleep 0.3

          expect(torn_down).to eq [value]
        end
      end

      context "with the inline worker (cannot defer)" do
        before { Plumbing::Actor.uses :inline }

        it "does not raise and caches forever — TTL is a silent no-op" do
          count = 0
          expect { provider.register(path: "counter", expires_in: 0.1) { count += 1 } }.not_to raise_error

          expect(provider["counter"]).to eq 1
          sleep 0.3
          expect(provider["counter"]).to eq 1
        end
      end

      it "raises if on_expiry is given without expires_in — the hook could never fire" do
        expect { provider.register(path: "svc", on_expiry: :stop) { Object.new }.await }.to raise_error ArgumentError
      end

      it "raises if a TTL is given for a static value — TTL requires a block provider" do
        expect { provider.register(path: "svc", value: Object.new, expires_in: 0.1).await }.to raise_error ArgumentError
      end
    end

    context "given a wildcard path" do
      it "only allows Providers to be registered under a wildcard" do
        object = Object.new

        expect { provider.register(path: "static/*", value: object).await }.to raise_error ArgumentError

        provider.register(path: "dynamic/*") { object }

        expect { provider["dynamic"] }.to raise_error ArgumentError
      end

      it "registers and returns a static provider" do
        other = Plumbing::Provider.new

        provider.register path: "other/*", value: other

        expect(provider["other"].object_id).to eq other.object_id
      end

      it "delegates paths to a static provider" do
        other = Plumbing::Provider.new
        other.register path: "say/hello", value: "Hello"

        provider.register path: "other/*", value: other

        expect(provider["other/say/hello"]).to eq "Hello"
      end

      it "registers and returns an on-demand provider" do
        other = Plumbing::Provider.new

        provider.register(path: "other/*") { other }

        expect(provider["other"].object_id).to eq other.object_id
      end

      it "delegates paths to an on-demand provider" do
        other = Plumbing::Provider.new
        other.register(path: "say/:something") { |something:| something.to_s.reverse }

        provider.register path: "other/*", value: other

        expect(provider["other/say/hello"]).to eq "olleh"
      end

      it "caches the on-demand provider so the block runs once" do
        builds = 0
        provider.register(path: "shared/*") do
          builds += 1
          inner = Plumbing::Provider.new
          inner.register(path: "x", value: "X")
          inner
        end

        expect(provider["shared/x"]).to eq "X"
        expect(provider["shared/x"]).to eq "X"
        expect(builds).to eq 1
      end
    end

    context "given a parameterised wildcard path" do
      it "passes the captured params to the registration block" do
        provider.register(path: "users/:user_id/messages/*") do |user_id:|
          inner = Plumbing::Provider.new
          inner.register(path: "latest", value: "message for #{user_id}")
          inner
        end

        expect(provider["users/42/messages/latest"]).to eq "message for 42"
      end

      it "returns the built provider at the bare parameterised prefix" do
        provider.register(path: "users/:user_id/messages/*") do |user_id:|
          inner = Plumbing::Provider.new
          inner.register(path: "self", value: user_id)
          inner
        end

        expect(provider["users/7/messages"]["self"]).to eq "7"
      end

      it "builds a differently-scoped provider per parameter value" do
        provider.register(path: "users/:user_id/docs/*") do |user_id:|
          inner = Plumbing::Provider.new
          inner.register(path: "whoami", value: user_id)
          inner
        end

        expect(provider["users/1/docs/whoami"]).to eq "1"
        expect(provider["users/2/docs/whoami"]).to eq "2"
      end

      it "caches one nested provider per parameter set" do
        builds = 0
        provider.register(path: "users/:user_id/docs/*") do |user_id:|
          builds += 1
          inner = Plumbing::Provider.new
          inner.register(path: "whoami", value: user_id)
          inner
        end

        provider["users/1/docs/whoami"]
        provider["users/1/docs/whoami"]
        expect(builds).to eq 1 # same param set → built once

        provider["users/2/docs/whoami"]
        expect(builds).to eq 2 # different param set → built again
      end

      it "rejects a static value under a parameterised wildcard" do
        other = Plumbing::Provider.new

        expect { provider.register(path: "users/:user_id/messages/*", value: other).await }.to raise_error ArgumentError
      end

      context "with a worker that can defer (threaded)" do
        before { Plumbing::Actor.uses :threaded }
        after { Plumbing::Actor.uses :inline }

        it "evicts and rebuilds the cached nested provider after expires_in" do
          builds = 0
          provider.register(path: "users/:user_id/docs/*", expires_in: 0.1) do |user_id:|
            builds += 1
            inner = Plumbing::Provider.new
            inner.register(path: "whoami", value: user_id)
            inner
          end

          provider["users/1/docs/whoami"]
          provider["users/1/docs/whoami"]
          expect(builds).to eq 1

          sleep 0.3

          provider["users/1/docs/whoami"]
          expect(builds).to eq 2 # cache evicted after the TTL, so rebuilt
        end

        it "runs on_expiry: :stop against each evicted nested provider" do
          built = []
          provider.register(path: "users/:user_id/docs/*", expires_in: 0.1, on_expiry: :stop) do |user_id:|
            Plumbing::Provider.new.tap { built << _1 }
          end

          provider["users/1/docs"]      # build and cache the nested provider
          expect(built.first.worker).to be_active

          sleep 0.3

          expect(built.first.worker).not_to be_active
        end
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
