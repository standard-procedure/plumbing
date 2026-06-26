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
          returns { "Hello" }
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
          returns { "Hello" }
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
          returns { "Hello" }
        end
      end

      instance = test_class.new
      message = instance.say_hello
      message.deliver
      expect(message.result).to eq "Hello"
    end
  end
end
