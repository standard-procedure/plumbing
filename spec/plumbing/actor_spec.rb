# frozen_string_literal: true

RSpec.describe Plumbing::Actor do
  describe "configuration" do
    after do
      Plumbing::Actor.uses :inline
      Plumbing::Actor.worker_types.delete(:my_worker)
    end

    it "always has the inline worker registered" do
      # Other workers (async/threaded/rails) self-register when required, so the
      # registry contains whatever has been required — inline is always present.
      expect(Plumbing::Actor.workers).to include(:inline)
    end

    it "allows new workers to be registered" do
      Plumbing::Actor.register :my_worker do |actor|
        "FAKE WORKER FOR #{actor}"
      end

      expect(Plumbing::Actor.workers).to include(:my_worker)
    end

    it "allows the current type of worker to be set" do
      Plumbing::Actor.register :my_worker do |actor|
        "FAKE WORKER FOR #{actor}"
      end

      Plumbing::Actor.uses :my_worker

      expect(Plumbing::Actor.worker_for("SOMEONE")).to eq "FAKE WORKER FOR SOMEONE"
    end
  end

  describe "definitions" do
    it "defines an asynchronous method using `returns`" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          returns { "Hello" }
        end
      end

      instance = test_class.new
      expect(instance).to respond_to(:say_hello)
    end

    it "defines an async method using `calls`" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :counter, _Integer, default: 0, reader: true

        async :increment do
          calls { @counter += 1 }
        end
      end

      instance = test_class.new
      expect(instance).to respond_to(:increment)
    end

    it "returns a message object when calling an async method" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          returns { "Hello" }
        end
      end

      instance = test_class.start
      result = instance.say_hello
      expect(result).to be_kind_of(Plumbing::Actor::Message)
    end

    it "awaits a return value from the async method" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          returns { "Hello" }
        end
      end

      instance = test_class.start
      result = await { instance.say_hello }
      expect(result).to eq "Hello"
    end

    it "allows blocks to be passed to async methods" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_something do
          returns do |&block|
            "I am speaking #{block.call}"
          end
        end
      end

      instance = test_class.start
      result = await { instance.say_something { "in a block" } }
      expect(result).to eq "I am speaking in a block"
    end

    it "defines callbacks before and after an async method is called" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :before_calls, Hash, default: -> { {} }, reader: :public
        prop :after_calls, Hash, default: -> { {} }, reader: :public

        before_message do |method, params|
          @before_calls[method] = params
        end

        after_message do |method, params, result|
          @after_calls[method] = result
        end

        async :say_hello do
          param :name, String
          returns do |name:|
            "Hello #{name}"
          end
        end
      end

      instance = test_class.start
      await { instance.say_hello name: "Alice" }

      expect(instance.before_calls.await[:say_hello]).to eq({name: "Alice"})
      expect(instance.after_calls.await[:say_hello]).to eq("Hello Alice")
    end
  end

  describe "properties" do
    it "creates properties but does not create read/write accessors by default" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :name, String

        async :get do
          returns { @name }
        end
      end

      test = test_class.new name: "Alice"
      expect(test.get.await).to eq "Alice"
      expect(test).to_not respond_to(:alice)
      expect(test).to_not respond_to(:"alice=")
    end

    it "creates an asynchronous reader for the property" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :name, String, reader: true
      end

      test = test_class.new name: "Alice"
      expect(test).to respond_to(:name)

      expect(test.name).to be_kind_of Plumbing::Actor::Message
      expect(test.name.await).to eq "Alice"
    end

    it "creates an asynchronous writer for the property" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :name, String, reader: true, writer: true
      end

      test = test_class.new name: "Alice"
      expect(test).to respond_to(:"name=")

      expect(test.name.await).to eq "Alice"
      await { test.name = "Bob" }
      expect(test.name.await).to eq "Bob"
    end
  end

  describe "starting" do
    it "builds a new actor and starts it automatically" do
      Plumbing::Actor.uses :inline

      test_class = Class.new do
        include Plumbing::Actor

        prop :started, _Boolean, default: false, reader: :public
        prop :name, String, reader: :public

        def after_start
          @started = true
        end
      end

      test = test_class.start name: "Alice"

      expect(test.name.await).to eq "Alice"
      expect(test.started.await).to be true
    end
  end
end
