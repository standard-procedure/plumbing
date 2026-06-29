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

RSpec.describe "Plumbing::Operations advance loop" do
  let(:doubler) do
    Class.new(Plumbing::Operations::Task) do
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
    klass = Class.new(Plumbing::Operations::Task) do
      attribute :flag, _Boolean
      starts_with :pick
      decision :pick do
        go_to :yes, "flag set", if: -> { flag }
      end
      result :yes
    end
    op = klass.call(flag: false)
    expect(op).to be_failed
    expect(op.exception).to be_a(Plumbing::Operations::NoDecision)
  end

  it "test(:state) drives the loop from a chosen state" do
    op = doubler.test(:double, n: 4)
    expect(op.current_state).to eq :done
    expect(op.result).to eq 8
  end
end

RSpec.describe "Plumbing::Operations events" do
  let(:doubler) do
    Class.new(Plumbing::Operations::Task) do
      attribute :n, Integer
      attribute :result, _Nilable(Integer)
      starts_with :double
      action(:double) { self.result = n * 2 }.then :done
      result :done
    end
  end

  it "emits Started, Transitioned and Completed to the pipeline in order" do
    events = []
    pipeline = Plumbing::Pipeline::Source.new
    pipeline.observe { |event| events << event }
    doubler.call(pipeline: pipeline, n: 5)
    expect(events.map(&:class)).to eq [
      Plumbing::Operations::Started,
      Plumbing::Operations::Transitioned,
      Plumbing::Operations::Completed
    ]
    expect(events.last.attributes).to eq({n: 5, result: 10})
    expect(events.last.state).to eq :done
  end

  it "works with no pipeline (events go nowhere)" do
    expect { doubler.call(n: 1) }.not_to raise_error
  end
end

RSpec.describe "Plumbing::Operations#to_mermaid" do
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

  it "renders the flowchart with the right shapes and labelled edges" do
    diagram = task_class.to_mermaid
    expect(diagram).to start_with("flowchart TD")
    expect(diagram).to include("start([Start]) --> check")
    expect(diagram).to include(%(check{"check"}))
    expect(diagram).to include(%(check -->|positive| double))
    expect(diagram).to include(%(check -->|non-positive| zero))
    expect(diagram).to include(%(double["double"] --> done))
    expect(diagram).to include(%(done(["done"])))
  end
end
