# frozen_string_literal: true

require "plumbing/operations"

RSpec.describe "Plumbing::Operations data types" do
  it "evaluates a Transition guard in the operation's context" do
    op = Object.new
    def op.ready? = true
    unconditional = Plumbing::Operations::Transition.new(target: :a, guard: nil, label: nil)
    guarded = Plumbing::Operations::Transition.new(target: :b, guard: -> { ready? }, label: "ok")
    expect(unconditional.matches?(op)).to be true
    expect(guarded.matches?(op)).to be true
  end

  it "defaults WaitOptions to 10s poll / 24h timeout" do
    expect(Plumbing::Operations::WaitOptions.new.delay).to eq 10.0
    expect(Plumbing::Operations::WaitOptions.new.timeout).to eq 86_400.0
  end

  it "builds a State with its kind constrained" do
    state = Plumbing::Operations::State.new(name: :go, kind: :result)
    expect(state.name).to eq :go
    expect(state.transitions).to eq []
    expect { Plumbing::Operations::State.new(name: :x, kind: :nonsense) }.to raise_error(StandardError)
  end
end

RSpec.describe "Plumbing::Operations attributes" do
  let(:task_class) do
    Class.new(Plumbing::Operations::Task) do
      attribute :count, Integer
      attribute :note, _Nilable(String)
    end
  end

  it "type-validates and exposes attributes through accessors" do
    op = task_class.new
    op.send(:setup_attributes, {count: 3})
    expect(op.count).to eq 3
    expect(op.note).to be_nil
    op.count = 5
    expect(op.count).to eq 5
    expect(op.attributes).to eq({count: 5, note: nil})
  end

  it "raises when a required attribute is missing or mistyped" do
    op = task_class.new
    expect { op.send(:setup_attributes, {count: "not-an-int"}) }.to raise_error(StandardError)
  end
end

RSpec.describe "Plumbing::Operations state DSL" do
  let(:task_class) do
    Class.new(Plumbing::Operations::Task) do
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
