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
    it "defines a simple async method" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          calls { "Hello" }
        end
      end

      instance = test_class.new
      expect(instance).to respond_to(:say_hello)
      expect(instance).to respond_to(:_say_hello)
    end

    it "returns a message object when calling an async method" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          calls { "Hello" }
        end
      end

      instance = test_class.new
      result = instance.say_hello
      expect(result).to be_kind_of(Plumbing::Actor::Message)
    end

    it "uses the message object to get a result from an async method" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_hello do
          calls { "Hello" }
        end
      end

      instance = test_class.new
      message = instance.say_hello
      message.deliver
      expect(message.result).to eq "Hello"
    end

    it "allows blocks to be passed to async methods" do
      test_class = Class.new do
        include Plumbing::Actor

        async :say_something do
          calls do |&block|
            "I am speaking #{block.call}"
          end
        end
      end

      instance = test_class.new
      message = instance.say_something { "in a block" }
      message.deliver
      expect(message.result).to eq "I am speaking in a block"
    end

    it "allows for before and after callbacks" do
      test_class = Class.new do
        include Plumbing::Actor

        prop :before_calls, Hash, default: -> { {} }, reader: :public
        prop :after_calls, Hash, default: -> { {} }, reader: :public

        before do |method, params|
          @before_calls[method] = params
        end

        after do |method, params, result|
          @after_calls[method] = result
        end

        async :say_hello do
          param :name, String
          calls do |name:|
            "Hello #{name}"
          end
        end
      end

      instance = test_class.start
      await { instance.say_hello name: "Alice" }

      expect(instance.before_calls[:say_hello]).to eq({name: "Alice"})
      expect(instance.after_calls[:say_hello]).to eq("Hello Alice")
    end
  end

  describe "starting" do
    it "builds a new actor and starts it automatically" do
      Plumbing::Actor.uses :inline

      test_class = Class.new do
        include Plumbing::Actor

        prop :started, _Boolean, default: false, reader: :public
        prop :name, String, reader: :public

        def before_start
          @started = true
        end
      end

      puts Plumbing::Actor.selected_worker_type

      test = test_class.start name: "Alice"

      expect(test.name).to eq "Alice"
      expect(test.started).to be true
    end
  end
end
