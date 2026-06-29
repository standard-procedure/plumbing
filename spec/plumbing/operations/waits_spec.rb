# frozen_string_literal: true

require "plumbing/operations"
require "plumbing/actor/async"
require "async"

RSpec.describe "Plumbing::Operations wait DSL" do
  let(:task_class) do
    Class.new(Plumbing::Operations::Task) do
      attribute :ready, _Boolean, default: false
      delay 0.05
      timeout 2.0
      starts_with :await_ready
      wait_until :await_ready do
        go_to :done, "ready", if: -> { ready }
      end
      wait_until :await_slow, delay: 0.5, timeout: 30.0 do
        go_to :done, "slow", if: -> { ready }
      end
      result :done
    end
  end

  it "records class-level delay and timeout defaults" do
    expect(task_class.default_delay).to eq 0.05
    expect(task_class.default_timeout).to eq 2.0
  end

  it "builds a :wait state using the class defaults" do
    state = task_class.states.fetch(:await_ready)
    expect(state.kind).to eq :wait
    expect(state.wait_options.delay).to eq 0.05
    expect(state.wait_options.timeout).to eq 2.0
    expect(state.transitions.map(&:target)).to eq [:done]
  end

  it "lets a wait override delay and timeout" do
    state = task_class.states.fetch(:await_slow)
    expect(state.wait_options.delay).to eq 0.5
    expect(state.wait_options.timeout).to eq 30.0
  end

  it "registers a Waiting event" do
    expect(Plumbing::Operations::Waiting.new(operation_id: 1, state: :await_ready, attributes: {}).state).to eq :await_ready
  end
end
