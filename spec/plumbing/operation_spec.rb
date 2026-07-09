# frozen_string_literal: true

RSpec.describe Plumbing::Operation do
  describe "definition" do
    let(:task_class) do
      Class.new(Plumbing::Operation) do
        attribute :n, Integer
        starts_with :check
        decision :check do
          go_to :double, "positive", if: -> { n > 0 }
          go_to :zero, "non-positive"
        end
        action(:double) { self.n = n * 2 }.then :done
        result :done
        result :zero
      end
    end

    it "records the start state" do
      expect(task_class.start_state).to eq :check
    end

    it "builds a decision with ordered, labelled transitions" do
      check = task_class.states.fetch(:check)
      expect(check.kind).to eq :decision
      expect(check.transitions.map(&:target)).to eq [:double, :zero]
      expect(check.transitions.map(&:label)).to eq ["positive", "non-positive"]
      expect(check.transitions.first.guard).to be_a(Proc)
      expect(check.transitions.last.guard).to be_nil
    end

    it "builds an action with a single then-transition" do
      double = task_class.states.fetch(:double)
      expect(double.kind).to eq :action
      expect(double.action).to be_a(Proc)
      expect(double.transitions.map(&:target)).to eq [:done]
    end

    it "builds result states with no transitions" do
      expect(task_class.states.fetch(:done).kind).to eq :result
      expect(task_class.states.fetch(:done).transitions).to eq []
    end
  end

  describe "run loop" do
    let(:doubler) do
      Class.new(Plumbing::Operation) do
        attribute :n, Integer
        attribute :result, _Nilable(Integer)
        starts_with :check
        decision :check do
          go_to :double, "positive", if: -> { n > 0 }
          go_to :zero, "non-positive"
        end
        action(:double) { self.result = n * 2 }.then :done
        result :done
        result :zero
      end
    end

    it "runs actions and decisions to a result, synchronously, on inline" do
      op = doubler.call(n: 3)
      expect(op).to be_completed
      expect(op.current_state).to eq :done
      expect(op.in?(:done)).to be true
      expect(op.result).to eq 6
    end

    it "follows the else branch when no guard matches the positive path" do
      op = doubler.call(n: -2)
      expect(op).to be_completed
      expect(op.current_state).to eq :zero
      expect(op.result).to be_nil
    end

    it "fails with NoDecision when a decision matches nothing" do
      klass = Class.new(Plumbing::Operation) do
        attribute :flag, _Boolean
        starts_with :pick
        decision :pick do
          go_to :yes, "flag set", if: -> { flag }
        end
        result :yes
      end
      op = klass.call(flag: false)
      expect(op).to be_failed
      expect(op.exception).to be_a(Plumbing::Operation::NoDecision)
    end

    it "test(:state) drives the loop from a chosen state" do
      op = doubler.test(:double, n: 4)
      expect(op.current_state).to eq :done
      expect(op.result).to eq 8
    end
  end
end
