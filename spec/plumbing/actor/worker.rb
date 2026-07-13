# frozen_string_literal: true

RSpec.shared_examples "a worker" do
  describe "calling" do
    let(:greeter) do
      Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          calls { |name:| "Hello #{name}" }
        end
      end
    end

    it "generates a message" do
      actor = greeter.start
      result = actor.greet name: "Alice"

      expect(result).to be_kind_of Plumbing::Actor::Message
      expect(result.await).to eq "Hello Alice"
    end

    it "marks the message as :done after delivery" do
      Sync do
        actor = greeter.start
        result = actor.greet name: "Alice"
        expect(result.await).to eq "Hello Alice"
        expect(result.status).to eq :done
      end
    end

    it "delivers multiple messages in order" do
      recorder = Class.new do
        include Plumbing::Actor

        prop :results, Array, default: -> { [] }, reader: true

        async :record do
          param :number, Integer

          calls do |number:|
            @results << number
          end
        end
      end

      actor = recorder.start

      (1..5).each { |i| actor.record(number: i) }

      results = await { actor.results }
      expect(results).to contain_exactly(1, 2, 3, 4, 5)
    end
  end

  describe "parameters" do
    let(:typed) do
      Class.new do
        include Plumbing::Actor

        async :greet do
          param :name, String
          param :age, _Integer(0..120), default: 42
          calls { |name:, age:| "#{name} is #{age}" }
        end
      end
    end

    it "applies defaults when params are omitted" do
      actor = typed.start
      result = await { actor.greet name: "Alice" }
      expect(result).to eq "Alice is 42"
    end

    it "re-raises any exceptions" do
      fail_class = Class.new do
        include Plumbing::Actor

        async :explode do
          calls { raise "BOOM" }
        end
      end

      actor = fail_class.start

      result = actor.explode
      expect { result.await }.to raise_error(RuntimeError)
    end

    it "raises Literal::TypeError on type mismatch" do
      actor = typed.start
      result = actor.greet name: 123
      expect { result.await }.to raise_error(Literal::TypeError)
    end

    it "raises ArgumentError when a required param is missing" do
      actor = typed.start
      result = actor.greet
      expect { result.await }.to raise_error(ArgumentError)
    end
  end
end
