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
