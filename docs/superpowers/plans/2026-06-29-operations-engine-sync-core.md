# Operations Engine — Synchronous Core (Plan 2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the synchronous core of `Plumbing::Operations::Task` — a state-machine engine (action / decision / result) authored with a readable class-method DSL, running on the inline worker, emitting events to an optional pipeline, and able to render itself as mermaid.

**Architecture:** A `Task` is a `Plumbing::Actor`. The DSL compiles `action`/`decision`/`result` declarations into immutable `Literal::Data` `State` objects held in a class-level map. Context lives in a per-class dynamic `Literal::Struct` exposed through generated accessors. A single `advance` method runs the synchronous loop (action → run body → next; decision → first matching guard → next; result → complete), emitting `Started`/`Transitioned`/`Completed`/`Failed` events to an optional pipeline. Waits, timeouts, interactions and restore are **Plan 2b** and are deliberately absent here.

**Tech Stack:** Ruby 4.x, Literal (`Literal::Data`, `Literal::Struct`, `Literal::Types`), the Plumbing actor + event/pipeline subsystems, RSpec, StandardRB.

This is **Plan 2a of the operations engine**; it depends on Plan 1 (`after`/`cancel_deferred`, already on `main`) only structurally — the sync core uses no deferral. Plan 2b adds `wait_until`/`timeout`/`interaction`/`restore` on top.

## Global Constraints

- `# frozen_string_literal: true` at the top of every Ruby file.
- StandardRB clean: run `bundle exec standardrb --fix <files>` before every commit.
- Run tests with `bundle exec rspec <path>`; run the full suite before the final commit.
- The `operations` subsystem is **opt-in**: specs `require "plumbing/operations"`. Do not auto-require it from `lib/plumbing.rb`.
- Namespace: `Plumbing::Operations`; base class `Plumbing::Operations::Task`.
- Operation handlers and guards run via `instance_exec` in the operation's context, so attributes are reachable as methods (`date`, `self.result = …`). Guards are procs; a `nil` guard is the unconditional "else".
- Events are emitted **after** the in-memory state change commits.
- Work on the `operations-engine` branch (already checked out). Do not push to `main`.
- Commit trailer on every commit: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

```
lib/plumbing/operations.rb                # NEW — opt-in require aggregator
lib/plumbing/operations/errors.rb         # NEW — Error/NoDecision/NoTransition (+ Timeout/InvalidState for 2b)
lib/plumbing/operations/transition.rb     # NEW — Transition (Literal::Data) + #matches?
lib/plumbing/operations/wait_options.rb   # NEW — WaitOptions (Literal::Data) [used by 2b]
lib/plumbing/operations/state.rb          # NEW — State (Literal::Data)
lib/plumbing/operations/events.rb         # NEW — Started/Transitioned/Completed/Failed + registration
lib/plumbing/operations/dsl.rb            # NEW — class-method DSL (attribute, starts_with, action, decision, result, call, test, builders)
lib/plumbing/operations/mermaid.rb        # NEW — to_mermaid
lib/plumbing/operations/task.rb           # NEW — base class: Actor + DSL + runtime (advance loop, emit, queries)
spec/plumbing/operations/sync_core_spec.rb  # NEW — end-to-end + unit specs
```

---

### Task 1: Data types and errors

**Files:**
- Create: `lib/plumbing/operations/errors.rb`, `lib/plumbing/operations/transition.rb`, `lib/plumbing/operations/wait_options.rb`, `lib/plumbing/operations/state.rb`, `lib/plumbing/operations.rb`
- Test: `spec/plumbing/operations/sync_core_spec.rb` (create)

**Interfaces:**
- Produces:
  - `Plumbing::Operations::Error < StandardError`, `NoDecision < Error`, `NoTransition < Error`, `Timeout < Error`, `InvalidState < Error`
  - `Plumbing::Operations::Transition` (`Literal::Data`) props `target: Symbol`, `guard: _Callable?`, `label: _Nilable(String)`; `#matches?(operation) -> Boolean` (`guard.nil? || operation.instance_exec(&guard)`)
  - `Plumbing::Operations::WaitOptions` (`Literal::Data`) props `delay: _Float = 10.0`, `timeout: _Float = 86_400.0`
  - `Plumbing::Operations::State` (`Literal::Data`) props `name: Symbol`, `kind: Plumbing.OneOf(:action,:decision,:wait,:result)`, `action: _Callable?`, `transitions: _Array(Transition) = [].freeze`, `wait_options: _Nilable(WaitOptions)`
  - `require "plumbing/operations"` loads the whole subsystem

- [ ] **Step 1: Write the failing test**

Create `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb`
Expected: FAIL — `cannot load such file -- plumbing/operations`.

- [ ] **Step 3: Create the error classes**

Create `lib/plumbing/operations/errors.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    Error = Class.new(StandardError)
    NoDecision = Class.new(Error)     # a decision matched no condition
    NoTransition = Class.new(Error)   # an action has no `.then`
    Timeout = Class.new(Error)        # a wait exceeded its timeout (Plan 2b)
    InvalidState = Class.new(Error)   # an interaction called in the wrong state (Plan 2b)
  end
end
```

- [ ] **Step 4: Create Transition**

Create `lib/plumbing/operations/transition.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    # One outgoing edge of a state. `guard` is a proc evaluated in the
    # operation's context; nil means unconditional (the "else" branch).
    # `label` is the human-readable mermaid edge text.
    class Transition < Literal::Data
      prop :target, Symbol
      prop :guard, _Callable?
      prop :label, _Nilable(String)

      def matches?(operation) = guard.nil? || operation.instance_exec(&guard)
    end
  end
end
```

- [ ] **Step 5: Create WaitOptions**

Create `lib/plumbing/operations/wait_options.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    # Poll/timeout configuration for a wait state. Durations are seconds;
    # the DSL coerces values via to_f. Consumed by Plan 2b.
    class WaitOptions < Literal::Data
      prop :delay, _Float, default: 10.0
      prop :timeout, _Float, default: 86_400.0
    end
  end
end
```

- [ ] **Step 6: Create State**

Create `lib/plumbing/operations/state.rb`:

```ruby
# frozen_string_literal: true

require_relative "transition"
require_relative "wait_options"

module Plumbing
  module Operations
    # A node in the state machine. `action` runs on entry (nil for
    # decision/result). `transitions` are ordered; the first matching guard
    # wins. `wait_options` is set only for :wait states (Plan 2b).
    class State < Literal::Data
      prop :name, Symbol
      prop :kind, Plumbing.OneOf(:action, :decision, :wait, :result)
      prop :action, _Callable?
      prop :transitions, _Array(Transition), default: [].freeze
      prop :wait_options, _Nilable(WaitOptions)
    end
  end
end
```

- [ ] **Step 7: Create the aggregator require**

Create `lib/plumbing/operations.rb`:

```ruby
# frozen_string_literal: true

require_relative "actor"
require_relative "event"
require_relative "pipeline"
require_relative "operations/errors"
require_relative "operations/transition"
require_relative "operations/wait_options"
require_relative "operations/state"
require_relative "operations/events"
require_relative "operations/dsl"
require_relative "operations/mermaid"
require_relative "operations/task"
```

> The `operations/events`, `operations/dsl`, `operations/mermaid`, `operations/task`
> requires point at files created in later tasks. Until Task 5 creates `events.rb`,
> comment out the four trailing requires so this task's spec can load; uncomment each as its
> file is created. (Task 5 adds events.rb; Tasks 3/4/6 add dsl/task/mermaid.)

For THIS task, `lib/plumbing/operations.rb` should end with only the requires whose files exist:

```ruby
require_relative "actor"
require_relative "event"
require_relative "pipeline"
require_relative "operations/errors"
require_relative "operations/transition"
require_relative "operations/wait_options"
require_relative "operations/state"
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 9: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations.rb lib/plumbing/operations/errors.rb lib/plumbing/operations/transition.rb lib/plumbing/operations/wait_options.rb lib/plumbing/operations/state.rb spec/plumbing/operations/sync_core_spec.rb
bundle exec rspec spec/plumbing/operations/sync_core_spec.rb
git add lib/plumbing/operations.rb lib/plumbing/operations/errors.rb lib/plumbing/operations/transition.rb lib/plumbing/operations/wait_options.rb lib/plumbing/operations/state.rb spec/plumbing/operations/sync_core_spec.rb
git commit -m "feat(operations): State/Transition/WaitOptions data types + errors

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Attributes (dynamic Literal::Struct + DSL)

**Files:**
- Create: `lib/plumbing/operations/dsl.rb`
- Create: `lib/plumbing/operations/task.rb` (minimal — enough to host the DSL and attribute storage)
- Modify: `lib/plumbing/operations.rb` (uncomment the `operations/dsl` and `operations/task` requires)
- Test: `spec/plumbing/operations/sync_core_spec.rb` (add)

**Interfaces:**
- Consumes: `Plumbing::Actor` (the base class includes it).
- Produces:
  - `Plumbing::Operations::DSL.attribute(name, type, **opts)` — adds a prop to the class's `attributes_schema` (a `Class.new(Literal::Struct)`) and defines delegating reader/writer instance methods.
  - `Plumbing::Operations::DSL.attributes_schema -> Class` (the per-class Literal::Struct).
  - `Plumbing::Operations::Task#attributes -> Hash` (the instance's attribute values).
  - `Plumbing::Operations::Task.new(pipeline: nil)`; internal `setup_attributes(attrs)` sets `@attributes`.

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "attributes"`
Expected: FAIL — `uninitialized constant Plumbing::Operations::Task`.

- [ ] **Step 3: Create the DSL module (attribute handling)**

Create `lib/plumbing/operations/dsl.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    # Class-level authoring DSL, extended onto Task. This file carries the
    # attribute mechanism; state builders are added in a later task.
    module DSL
      # The per-class Literal::Struct that holds attribute values. Mutable, so
      # actions can assign (self.x = ...).
      def attributes_schema
        @attributes_schema ||= Class.new(Literal::Struct)
      end

      # Declare a typed attribute. Adds a prop to the schema and defines
      # delegating reader/writer methods on instances.
      def attribute(name, type, **opts)
        attributes_schema.prop(name, type, **opts)
        define_method(name) { @attributes.public_send(name) }
        define_method(:"#{name}=") { |value| @attributes.public_send(:"#{name}=", value) }
        name.to_sym
      end
    end
  end
end
```

- [ ] **Step 4: Create the Task base class (minimal)**

Create `lib/plumbing/operations/task.rb`:

```ruby
# frozen_string_literal: true

require_relative "dsl"

module Plumbing
  module Operations
    # Base class for operations. Subclass it and declare attributes + states
    # with the DSL. A Task is a Plumbing::Actor.
    class Task
      include Plumbing::Actor
      extend Literal::Types
      extend DSL

      def initialize(pipeline: nil)
        super()
        @pipeline = pipeline
        @status = :pending
      end

      def attributes = @attributes.to_h

      private

      def setup_attributes(attrs)
        @attributes = self.class.attributes_schema.new(**attrs)
      end
    end
  end
end
```

- [ ] **Step 5: Wire the requires**

In `lib/plumbing/operations.rb`, append (after the `operations/state` require):

```ruby
require_relative "operations/dsl"
require_relative "operations/task"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "attributes"`
Expected: PASS (2 examples).

- [ ] **Step 7: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations.rb lib/plumbing/operations/dsl.rb lib/plumbing/operations/task.rb spec/plumbing/operations/sync_core_spec.rb
bundle exec rspec spec/plumbing/operations/sync_core_spec.rb
git add lib/plumbing/operations.rb lib/plumbing/operations/dsl.rb lib/plumbing/operations/task.rb spec/plumbing/operations/sync_core_spec.rb
git commit -m "feat(operations): typed attributes via a per-class Literal::Struct

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: State-building DSL (starts_with, action/.then, decision/go_to, result)

**Files:**
- Modify: `lib/plumbing/operations/dsl.rb` (add state builders)
- Test: `spec/plumbing/operations/sync_core_spec.rb` (add)

**Interfaces:**
- Consumes: `Plumbing::Operations::State`, `Plumbing::Operations::Transition`.
- Produces (class methods on a Task subclass):
  - `starts_with(name) -> Symbol`; `start_state -> Symbol`
  - `states -> Hash{Symbol => State}`
  - `action(name, &body) -> ActionBuilder` whose `#then(target) -> Symbol` sets the action's single transition
  - `decision(name, &block) -> Symbol`; inside the block, `go_to(target, label = nil, **opts)` where `opts[:if]` is the guard proc
  - `result(name) -> Symbol`

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "state DSL"`
Expected: FAIL — `undefined method 'starts_with'`.

- [ ] **Step 3: Add the state builders to the DSL**

In `lib/plumbing/operations/dsl.rb`, add `require_relative "state"` at the top (after `# frozen_string_literal: true`), and add these methods inside `module DSL`:

```ruby
      def states = @states ||= {}

      def starts_with(name) = @start_state = name.to_sym

      def start_state = @start_state

      def action(name, &body)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :action, action: body)
        ActionBuilder.new(self, name.to_sym)
      end

      def decision(name, &block)
        builder = DecisionBuilder.new
        builder.instance_eval(&block)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :decision, transitions: builder.transitions.freeze)
        name.to_sym
      end

      def result(name)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :result)
        name.to_sym
      end
```

And add these two builder classes inside `module Operations` (below the `module DSL ... end`, still in `dsl.rb`):

```ruby
    # Returned by `action` so `.then` can set its single transition.
    class ActionBuilder
      def initialize(klass, name)
        @klass = klass
        @name = name
      end

      def then(target)
        state = @klass.states.fetch(@name)
        @klass.states[@name] = State.new(**state.to_h.merge(transitions: [Transition.new(target: target.to_sym, guard: nil, label: nil)].freeze))
        @name
      end
    end

    # Collects `go_to` calls inside a `decision` block.
    class DecisionBuilder
      attr_reader :transitions

      def initialize = @transitions = []

      def go_to(target, label = nil, **opts)
        @transitions << Transition.new(target: target.to_sym, guard: opts[:if], label: label)
      end
    end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "state DSL"`
Expected: PASS (4 examples).

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/dsl.rb spec/plumbing/operations/sync_core_spec.rb
bundle exec rspec spec/plumbing/operations/sync_core_spec.rb
git add lib/plumbing/operations/dsl.rb spec/plumbing/operations/sync_core_spec.rb
git commit -m "feat(operations): state-building DSL (starts_with/action/decision/result)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The advance loop (call, action/decision/result, failure, queries)

**Files:**
- Modify: `lib/plumbing/operations/task.rb` (add `call`, `advance`, the loop, `move_to`, queries)
- Modify: `lib/plumbing/operations/dsl.rb` (add `call` / `test` class methods)
- Test: `spec/plumbing/operations/sync_core_spec.rb` (add)

**Interfaces:**
- Consumes: `States`/`start_state`/`attributes_schema` (Task 3), `Transition#matches?` (Task 1), `NoDecision`/`NoTransition` (Task 1).
- Produces:
  - `Task.call(pipeline: nil, **attrs) -> Task` — runs to completion on the inline worker.
  - `Task.test(state, pipeline: nil, **attrs) -> Task` — positions at `state` then runs.
  - instance `advance` (async; one synchronous run of the loop), `current_state -> Symbol`, `in?(name) -> Boolean`, `completed? -> Boolean`, `failed? -> Boolean`, `exception -> Exception?`.
  - On a decision with no matching transition → `NoDecision`; on an action with no `.then` → `NoTransition`; either is caught and the operation is marked `failed?` with `exception` set.

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "advance loop"`
Expected: FAIL — `undefined method 'call'` for the class.

- [ ] **Step 3: Add `call`/`test` to the DSL**

In `lib/plumbing/operations/dsl.rb`, add inside `module DSL`:

```ruby
      def call(pipeline: nil, **attrs)
        new(pipeline: pipeline).tap { |op| op.__send__(:start, attrs) }
      end

      def test(state, pipeline: nil, **attrs)
        new(pipeline: pipeline).tap { |op| op.__send__(:start_at, state.to_sym, attrs) }
      end
```

- [ ] **Step 4: Add the runtime to Task**

In `lib/plumbing/operations/task.rb`, add these methods to the `Task` class. The `advance` async method and the private loop:

```ruby
      async :advance do
        returns { run_loop }
      end

      def current_state = @current_state

      def in?(name) = @current_state == name.to_sym

      def completed? = @status == :completed

      def failed? = @status == :failed

      attr_reader :exception
```

and add to the `private` section (below `setup_attributes`):

```ruby
      def start(attrs)
        setup_attributes(attrs)
        @current_state = self.class.start_state
        enter_running
        advance
      end

      def start_at(state, attrs)
        setup_attributes(attrs)
        @current_state = state
        enter_running
        advance
      end

      def enter_running
        @status = :running
        emit Started.new(operation_id: object_id, state: @current_state, attributes: attributes)
      end

      def run_loop
        loop do
          state = self.class.states.fetch(@current_state)
          case state.kind
          when :result
            @status = :completed
            emit Completed.new(operation_id: object_id, state: state.name, attributes: attributes)
          when :action
            instance_exec(&state.action) if state.action
            transition = state.transitions.first
            raise NoTransition, "action :#{state.name} needs a `.then`" if transition.nil?
            move_to(transition)
          when :decision
            transition = state.transitions.find { |t| t.matches?(self) }
            raise NoDecision, "no condition matched in :#{state.name}" if transition.nil?
            move_to(transition)
          end
          break unless @status == :running
        end
      rescue => ex
        @status = :failed
        @exception = ex
        emit Failed.new(operation_id: object_id, state: @current_state, exception: ex, attributes: attributes)
      end

      def move_to(transition)
        from = @current_state
        @current_state = transition.target
        emit Transitioned.new(operation_id: object_id, from: from, to: @current_state, via: transition.label, attributes: attributes)
      end

      def emit(event) = @pipeline&.push(event: event)
```

> Note: `run_loop` `break`s out of the `loop` only when the status leaves `:running`
> (result reached or an exception set `@status = :failed`). On the inline worker `advance`
> delivers synchronously, so `call` returns after the operation has finished. Wait states
> are not handled here — that is Plan 2b.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "advance loop"`
Expected: FAIL — `uninitialized constant Plumbing::Operations::Started` (events not built until Task 5).

This is expected: the loop references the event classes. To prove the loop logic in isolation first, temporarily stub the events by running ONLY the non-event assertions is not possible (emit is on the happy path). Therefore Task 4 and Task 5 are committed together: proceed to Task 5, create the events, then run this spec and Task 5's spec, and commit both. Do NOT commit Task 4 alone.

- [ ] **Step 6: Defer commit to Task 5**

Leave the working tree as-is and continue to Task 5. (The events the loop emits are created there; committing now would leave the suite red.)

---

### Task 5: Events + emission, committed with the loop

**Files:**
- Create: `lib/plumbing/operations/events.rb`
- Modify: `lib/plumbing/operations.rb` (add the `operations/events` require, before `operations/task`)
- Test: `spec/plumbing/operations/sync_core_spec.rb` (add an events example)

**Interfaces:**
- Consumes: `Plumbing::Event`, `Plumbing::Pipeline.register`, `Plumbing::Pipeline::Source` (test).
- Produces (all `Plumbing::Event` subclasses, registered):
  - `Started(operation_id: Integer, state: Symbol, attributes: Hash)`
  - `Transitioned(operation_id: Integer, from: Symbol, to: Symbol, via: _Nilable(String), attributes: Hash)`
  - `Completed(operation_id: Integer, state: Symbol, attributes: Hash)`
  - `Failed(operation_id: Integer, state: Symbol, exception: Exception, attributes: Hash)`

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "events"`
Expected: FAIL — `uninitialized constant Plumbing::Operations::Started`.

- [ ] **Step 3: Create the event classes**

Create `lib/plumbing/operations/events.rb`:

```ruby
# frozen_string_literal: true

require_relative "../event"
require_relative "../pipeline"

module Plumbing
  module Operations
    # Lifecycle events. Each checkpoint carries the operation id, the current
    # state, and a full attributes snapshot — enough for a persistence observer
    # to upsert (operation_id, state, attributes).
    class Started < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :attributes, Hash
    end

    class Transitioned < Plumbing::Event
      prop :operation_id, Integer
      prop :from, Symbol
      prop :to, Symbol
      prop :via, _Nilable(String)
      prop :attributes, Hash
    end

    class Completed < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :attributes, Hash
    end

    class Failed < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :exception, Exception
      prop :attributes, Hash
    end

    [Started, Transitioned, Completed, Failed].each { |klass| Plumbing::Pipeline.register(klass) }
  end
end
```

- [ ] **Step 4: Wire the require**

In `lib/plumbing/operations.rb`, add (before the `operations/dsl` require):

```ruby
require_relative "operations/events"
```

- [ ] **Step 5: Run the loop + events specs to verify they pass**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "advance loop"`
Expected: PASS (4 examples).

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "events"`
Expected: PASS (2 examples).

- [ ] **Step 6: StandardRB and commit (loop + events together)**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations.rb lib/plumbing/operations/events.rb lib/plumbing/operations/task.rb lib/plumbing/operations/dsl.rb spec/plumbing/operations/sync_core_spec.rb
bundle exec rspec spec/plumbing/operations/sync_core_spec.rb
git add lib/plumbing/operations.rb lib/plumbing/operations/events.rb lib/plumbing/operations/task.rb lib/plumbing/operations/dsl.rb spec/plumbing/operations/sync_core_spec.rb
git commit -m "feat(operations): advance loop (action/decision/result) + lifecycle events

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: to_mermaid

**Files:**
- Create: `lib/plumbing/operations/mermaid.rb`
- Modify: `lib/plumbing/operations.rb` (add `operations/mermaid` require), `lib/plumbing/operations/task.rb` (`extend Mermaid`)
- Test: `spec/plumbing/operations/sync_core_spec.rb` (add)

**Interfaces:**
- Consumes: `states`, `start_state` (Task 3), `State#kind`, `State#transitions`, `Transition#label`/`#target`.
- Produces: `Task.to_mermaid -> String` — a `flowchart TD` using `([Start])` start, `["…"]` action, `{"…"}` decision, `{{"…"}}` wait, `(["…"])` result; edges `from -->|label| to`, or bare `-->` when label is nil.

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/sync_core_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "to_mermaid"`
Expected: FAIL — `undefined method 'to_mermaid'`.

- [ ] **Step 3: Create the mermaid renderer**

Create `lib/plumbing/operations/mermaid.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    # Renders a Task's states as a mermaid `flowchart TD`. Pure function of the
    # class's States — the structure is real; only edge labels are author text.
    module Mermaid
      SHAPES = {
        action: ->(name) { %(#{name}["#{name}"]) },
        decision: ->(name) { %(#{name}{"#{name}"}) },
        wait: ->(name) { %(#{name}{{"#{name}"}}) },
        result: ->(name) { %(#{name}(["#{name}"])) }
      }.freeze

      def to_mermaid
        lines = ["flowchart TD", "  start([Start]) --> #{start_state}"]
        states.each_value do |state|
          lines << "  #{SHAPES.fetch(state.kind).call(state.name)}"
          state.transitions.each do |transition|
            edge = transition.label.nil? ? "-->" : "-->|#{transition.label}|"
            lines << "  #{state.name} #{edge} #{transition.target}"
          end
        end
        lines.join("\n")
      end
    end
  end
end
```

- [ ] **Step 4: Wire it in**

In `lib/plumbing/operations.rb`, add (after `operations/dsl`):

```ruby
require_relative "operations/mermaid"
```

In `lib/plumbing/operations/task.rb`, add `require_relative "mermaid"` at the top (after `require_relative "dsl"`) and add `extend Mermaid` to the class (right after `extend DSL`).

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/sync_core_spec.rb -e "to_mermaid"`
Expected: PASS (1 example).

> The node line `check{"check"}` and the edge line `check -->|positive| double` are two
> separate lines; the test asserts both as substrings, so ordering within the file does not
> matter.

- [ ] **Step 6: Run the FULL suite, StandardRB, and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations.rb lib/plumbing/operations/mermaid.rb lib/plumbing/operations/task.rb spec/plumbing/operations/sync_core_spec.rb
bundle exec rspec
git add lib/plumbing/operations.rb lib/plumbing/operations/mermaid.rb lib/plumbing/operations/task.rb spec/plumbing/operations/sync_core_spec.rb
git commit -m "feat(operations): to_mermaid renderer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (vs the design's Spec 1, sync-core portion):**
- Unified `Literal::Data` State/Transition/WaitOptions model → Task 1. ✓
- Familiar DSL (`attribute`, `starts_with`, `action`/`.then`, `decision`/`go_to`, `result`) compiling to States → Tasks 2, 3. ✓
- Literal-typed attributes with presence-via-nilability, accessors, `attributes` snapshot → Task 2. ✓
- advance loop for action/decision/result, `NoDecision`/`NoTransition`, `call`/queries, `instance_exec` handlers → Task 4. ✓
- Events (Started/Transitioned/Completed/Failed) carrying `{operation_id, state, attributes}`, emitted to an optional pipeline, after the commit → Task 5. ✓
- `to_mermaid` with the documented shapes + author-supplied edge labels → Task 6. ✓
- `test(:state, **attrs)` helper → Task 4. ✓
- **Deferred to Plan 2b (correctly absent here):** `wait_until`, `delay`/`timeout` class setters, `interaction`/`.when`, the wait poll/timeout via `after`/`cancel_deferred`, the generation token, `restore`, `InvalidState`/`Timeout` raising. `WaitOptions`, `Timeout`, `InvalidState` are defined now (Task 1) but unused until 2b — intentional.

**2. Placeholder scan:** No TBD/TODO/"handle errors"/"similar to". Every code step shows complete code; every command has expected output. The one cross-task coupling (Task 4's loop emits events created in Task 5) is made explicit: Task 4 does not commit; Tasks 4+5 commit together. ✓

**3. Type consistency:** `State` props (`name`/`kind`/`action`/`transitions`/`wait_options`), `Transition` (`target`/`guard`/`label`) and `#matches?`, `attributes_schema`/`attribute`/`attributes`, `states`/`start_state`, `advance`/`run_loop`/`move_to`/`emit`, the four event signatures, and `call`/`test`/`current_state`/`in?`/`completed?`/`failed?`/`exception` are named identically across the Interfaces blocks and the code steps. ✓

## Notes for Plan 2b

- `WaitOptions`, `Timeout`, `InvalidState` already exist (Task 1). 2b adds: `wait_until(name, delay:, timeout:, &block)` (builds a `:wait` State with `wait_options`, coercing durations via `to_f`), the `delay`/`timeout` class-level default setters, the `:wait` arm of `run_loop` (evaluate guards; matched → `move_to` and continue; unmatched → schedule poll `after(delay, call: :advance)` + timeout, remember ids + a generation token, then `break`), `interaction(name, &body).when(state)`, and `restore(state:, wait_started_at:, **attrs)`.
- Under the inline worker a wait must surface `Plumbing::Actor::NotSupported` (from `after`); 2b should also add a friendlier early guard. Wait-bearing operations require the global worker to be `:async`/`:threaded`.
- 2b's wait tests run inside `Sync do |task| … end` and advance time with `task.sleep`, per Plan 1's spec.
