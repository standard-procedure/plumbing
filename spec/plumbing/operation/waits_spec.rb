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

RSpec.describe "Plumbing::Operations wait runtime" do
  before do
    Plumbing::Actor.register(:async) { |actor| Plumbing::Actor::Async.new(actor: actor) }
    Plumbing::Actor.uses :async
  end

  after do
    Plumbing::Actor.uses :inline
    Plumbing::Actor.worker_types.delete(:async)
  end

  let(:gate) { Struct.new(:open).new(false) }

  let(:poll_waiter) do
    Class.new(Plumbing::Operations::Task) do
      attribute :gate, _Any?
      delay 0.03
      timeout 5.0
      starts_with :await_gate
      wait_until :await_gate do
        go_to :done, "gate open", if: -> { gate.open }
      end
      result :done
    end
  end

  it "stays in the wait until an external change satisfies the guard at the next poll" do
    Sync do |task|
      op = poll_waiter.call(gate: gate)
      task.sleep 0.02
      expect(op.current_state).to eq :await_gate
      expect(op).not_to be_completed
      gate.open = true
      task.sleep 0.1
      expect(op).to be_completed
      expect(op.current_state).to eq :done
    end
  end

  it "fails with Timeout when the guard never satisfies" do
    short = Class.new(Plumbing::Operations::Task) do
      attribute :gate, _Any?
      delay 0.02
      timeout 0.05
      starts_with :forever
      wait_until :forever do
        go_to :done, "never", if: -> { false }
      end
      result :done
    end
    Sync do |task|
      op = short.call(gate: gate)
      task.sleep 0.3
      expect(op).to be_failed
      expect(op.exception).to be_a(Plumbing::Operations::Timeout)
    end
  end

  let(:registration) do
    Class.new(Plumbing::Operations::Task) do
      attribute :name, _Nilable(String)
      delay 0.05
      timeout 5.0
      starts_with :await_name
      wait_until :await_name do
        go_to :greet, "named", if: -> { !name.nil? }
      end
      action(:greet) { self.name = "Hello #{name}" }.then :done
      result :done
      interaction(:provide_name) { |value| self.name = value }.when :await_name
    end
  end

  it "wakes a waiting operation immediately via an interaction" do
    Sync do |task|
      op = registration.call
      task.sleep 0.02
      expect(op.current_state).to eq :await_name
      op.provide_name("Cher")
      task.sleep 0.02
      expect(op).to be_completed
      expect(op.name).to eq "Hello Cher"
    end
  end

  it "raises InvalidState when an interaction is called in the wrong state" do
    Sync do |task|
      op = registration.call
      task.sleep 0.02
      op.provide_name("Cher")
      task.sleep 0.02
      expect(op).to be_completed
      expect { op.provide_name("Dionne").await }.to raise_error(Plumbing::Operations::InvalidState)
    end
  end

  it "restores an operation into a wait and resumes it" do
    Sync do |task|
      op = poll_waiter.restore(state: :await_gate, gate: gate, wait_elapsed: 1.0)
      task.sleep 0.02
      expect(op.current_state).to eq :await_gate
      expect(op).not_to be_completed
      gate.open = true
      task.sleep 0.1
      expect(op).to be_completed
    end
  end
end

RSpec.describe "Plumbing::Operations wait under the inline worker" do
  before { Plumbing::Actor.uses :inline }

  it "raises NotSupported up front" do
    klass = Class.new(Plumbing::Operations::Task) do
      attribute :gate, _Any?
      starts_with :await_gate
      wait_until :await_gate do
        go_to :done, "open", if: -> { gate.open }
      end
      result :done
    end
    expect { klass.call(gate: Struct.new(:open).new(false)) }.to raise_error(Plumbing::Actor::NotSupported)
  end
end
