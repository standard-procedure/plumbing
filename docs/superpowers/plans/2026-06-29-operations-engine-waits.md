# Operations Engine — Waits, Interactions & Restore (Plan 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the asynchronous half of `Plumbing::Operations::Task` — `wait_until` states that poll a guard on a timer (with a timeout), `interaction` methods that wake a waiting operation, and `restore` to rehydrate one — built on Plan 1's `after`/`cancel_deferred`.

**Architecture:** A `:wait` state, when its guards don't yet match, schedules a deferred `advance` `delay` seconds out (a "poll") via the worker's `after`, and breaks the loop; the operation stays responsive. When the poll (or an `interaction`, or a purely external change at the next poll) re-runs `advance`, the guard is re-evaluated. Timeout is enforced by a monotonic-clock elapsed check, tripped by a second deferred `advance` scheduled at `timeout`. A generation token discards stale polls left over from a wait the operation has already left. Wait-bearing operations require the global worker to be `:async`/`:threaded`; on `:inline` they raise `Plumbing::Actor::NotSupported`.

**Tech Stack:** Ruby 4.x, Literal, the Plumbing actor (`after`/`cancel_deferred` from Plan 1), `async` gem (test reactor), RSpec, StandardRB.

This is **Plan 2b**, on top of Plan 2a (the synchronous core, already on `main`) and Plan 1 (`after`/`cancel_deferred`, on `main`).

## Global Constraints

- `# frozen_string_literal: true` atop every Ruby file.
- StandardRB clean: `bundle exec standardrb --fix <files>` before every commit.
- Run tests with `bundle exec rspec <path>`; full suite before the final commit.
- Operations stays opt-in (`require "plumbing/operations"`); wait tests also `require "plumbing/actor/async"` and `require "async"`.
- Async wait tests run inside `Sync do |task| … end` and advance time with `task.sleep` (a bare `sleep` blocks the reactor). Worker selection is global: `before { Plumbing::Actor.register(:async){…}; Plumbing::Actor.uses :async }`, `after { Plumbing::Actor.uses :inline; Plumbing::Actor.worker_types.delete(:async) }`.
- Handlers/guards run via `instance_exec`; events emitted after the in-memory change commits.
- Work on the `operations-waits` branch (already checked out). Do not push to `main`.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

```
lib/plumbing/operations/dsl.rb        # MOD — wait_until, delay, timeout, interaction/.when, restore, interaction_states; inline-worker guard
lib/plumbing/operations/events.rb     # MOD — add Waiting event
lib/plumbing/operations/task.rb       # MOD — advance token param; start/worker.call; :wait loop arm; enter/leave/poll/timeout helpers; interaction handler; resume
spec/plumbing/operations/waits_spec.rb   # NEW — wait/timeout/interaction/restore (async) + inline guard
```

---

### Task 1: wait_until / delay / timeout DSL + Waiting event

**Files:**
- Modify: `lib/plumbing/operations/dsl.rb`
- Modify: `lib/plumbing/operations/events.rb`
- Test: `spec/plumbing/operations/waits_spec.rb` (create)

**Interfaces:**
- Consumes: `State`, `Transition`, `WaitOptions`, `DecisionBuilder` (Plan 2a).
- Produces (class methods):
  - `delay(seconds) -> Float` / `default_delay -> Float` (default 10.0); `timeout(seconds) -> Float` / `default_timeout -> Float` (default 86_400.0). Setters coerce via `to_f`.
  - `wait_until(name, delay: nil, timeout: nil, &block) -> Symbol` — builds a `:wait` State whose `wait_options` uses the given delay/timeout or the class defaults; the block uses the same `go_to` as `decision`.
  - `Plumbing::Operations::Waiting(operation_id: Integer, state: Symbol, attributes: Hash)` event (registered).

- [ ] **Step 1: Write the failing test**

Create `spec/plumbing/operations/waits_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb`
Expected: FAIL — `undefined method 'delay'` for the class.

- [ ] **Step 3: Add the Waiting event**

In `lib/plumbing/operations/events.rb`, add the class (before the registration line) and include it in the registration array:

```ruby
    class Waiting < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :attributes, Hash
    end
```

Change the registration line to:

```ruby
    [Started, Transitioned, Waiting, Completed, Failed].each { |klass| Plumbing::Pipeline.register(klass) }
```

- [ ] **Step 4: Add the wait DSL**

In `lib/plumbing/operations/dsl.rb`, add inside `module DSL`:

```ruby
      def delay(seconds) = @default_delay = seconds.to_f

      def default_delay = @default_delay ||= 10.0

      def timeout(seconds) = @default_timeout = seconds.to_f

      def default_timeout = @default_timeout ||= 86_400.0

      def wait_until(name, delay: nil, timeout: nil, &block)
        builder = DecisionBuilder.new
        builder.instance_eval(&block)
        options = WaitOptions.new(delay: (delay || default_delay).to_f, timeout: (timeout || default_timeout).to_f)
        states[name.to_sym] = State.new(name: name.to_sym, kind: :wait, transitions: builder.transitions.freeze, wait_options: options)
        name.to_sym
      end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 6: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/dsl.rb lib/plumbing/operations/events.rb spec/plumbing/operations/waits_spec.rb
bundle exec rspec spec/plumbing/operations/waits_spec.rb
git add lib/plumbing/operations/dsl.rb lib/plumbing/operations/events.rb spec/plumbing/operations/waits_spec.rb
git commit -m "feat(operations): wait_until / delay / timeout DSL + Waiting event

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The wait runtime (poll, timeout, generation token, inline guard)

**Files:**
- Modify: `lib/plumbing/operations/task.rb`
- Modify: `lib/plumbing/operations/dsl.rb` (inline-worker guard in `call`)
- Test: `spec/plumbing/operations/waits_spec.rb` (add)

**Interfaces:**
- Consumes: `after(delay, call:, **params)` / `cancel_deferred(id)` (Plan 1), `WaitOptions`, `Timeout`, `Waiting`, `Plumbing::Actor::NotSupported`, `Plumbing::Actor.selected_worker_type`.
- Produces:
  - `advance(poll_token: nil)` — re-evaluates the current state; a poll whose token is stale is ignored.
  - `:wait` arm of `run_loop`: guard matched → leave the wait and `move_to`; timed out → leave and raise `Timeout`; else schedule a poll and `break`.
  - `call`/`test` raise `Plumbing::Actor::NotSupported` up front if the operation has any `:wait` state and the global worker is `:inline`.
  - `start`/`start_at` call `worker.call` so async/threaded operations self-start (inline `call` is a no-op).

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/waits_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "wait runtime"`
Expected: FAIL — the operation does not handle `:wait` (run_loop has no `:wait` arm; `KeyError`/infinite behaviour or it raising because `after` is reached without the arm). The inline test fails because no guard is raised.

- [ ] **Step 3: Add the inline-worker guard to `call`/`test`**

In `lib/plumbing/operations/dsl.rb`, replace the existing `call` and `test` methods with:

```ruby
      def call(pipeline: nil, **attrs)
        ensure_worker_supports_waits!
        new(pipeline: pipeline).tap { |op| op.__send__(:start, attrs) }
      end

      def test(state, pipeline: nil, **attrs)
        ensure_worker_supports_waits!
        new(pipeline: pipeline).tap { |op| op.__send__(:start_at, state.to_sym, attrs) }
      end

      def has_waits? = states.each_value.any? { |state| state.kind == :wait }

      def ensure_worker_supports_waits!
        return unless has_waits?
        return unless Plumbing::Actor.selected_worker_type == :inline
        raise Plumbing::Actor::NotSupported, "#{name || "operation"} has wait states; select a non-inline worker with Plumbing::Actor.uses :async (or :threaded)"
      end
```

- [ ] **Step 4: Add the wait runtime to `Task`**

In `lib/plumbing/operations/task.rb`:

(a) In `initialize`, after `@status = :pending`, add:

```ruby
        @wait_generation = 0
```

(b) Replace the `advance` async declaration with one that takes a poll token:

```ruby
      async :advance do
        param :poll_token, _Nilable(Integer), default: nil
        returns { |poll_token:| run_loop unless stale_poll?(poll_token) }
      end
```

(c) In the `private` section, change `start` and `start_at` to start the worker before advancing:

```ruby
      def start(attrs)
        setup_attributes(attrs)
        @current_state = self.class.start_state
        enter_running
        worker.call
        advance
      end

      def start_at(state, attrs)
        setup_attributes(attrs)
        @current_state = state
        enter_running
        worker.call
        advance
      end
```

(d) Add the `:wait` arm to `run_loop`. The full `run_loop` becomes:

```ruby
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
          when :wait
            enter_wait(state) unless @waiting_state == state.name
            transition = state.transitions.find { |t| t.matches?(self) }
            if transition
              leave_wait
              move_to(transition)
            elsif timed_out?(state)
              leave_wait
              raise Timeout, "wait :#{state.name} exceeded #{state.wait_options.timeout}s"
            else
              reschedule_poll(state)
              break
            end
          end
          break unless @status == :running
        end
      rescue => ex
        leave_wait
        @status = :failed
        @exception = ex
        emit Failed.new(operation_id: object_id, state: @current_state, exception: ex, attributes: attributes)
      end
```

(e) Add these private helpers (e.g. after `move_to`):

```ruby
      def stale_poll?(token) = !token.nil? && token != @wait_generation

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def enter_wait(state)
        @waiting_state = state.name
        @wait_generation += 1
        @wait_started_at = monotonic - (@restored_wait_elapsed || 0.0)
        @restored_wait_elapsed = nil
        @timeout_id = after(state.wait_options.timeout, call: :advance, poll_token: @wait_generation)
        emit Waiting.new(operation_id: object_id, state: state.name, attributes: attributes)
      end

      def reschedule_poll(state)
        cancel_deferred(@poll_id) if @poll_id
        @poll_id = after(state.wait_options.delay, call: :advance, poll_token: @wait_generation)
      end

      def timed_out?(state)
        return false if @wait_started_at.nil?
        (monotonic - @wait_started_at) >= state.wait_options.timeout
      end

      def leave_wait
        cancel_deferred(@poll_id) if @poll_id
        cancel_deferred(@timeout_id) if @timeout_id
        @wait_generation += 1
        @poll_id = @timeout_id = @waiting_state = @wait_started_at = nil
      end
```

> How it fits together: on entering a fresh wait, `enter_wait` stamps the start time, bumps the
> generation, and schedules a timeout `advance` at `timeout`. Each unmatched evaluation
> `reschedule_poll`s a fresh poll `delay` out (cancelling the prior one) and `break`s. A poll/
> timeout/interaction re-runs `advance`; the loop re-enters the `:wait` arm (now `@waiting_state ==
> state.name`, so it does not re-enter), re-evaluates the guard, and either moves on, times out, or
> polls again. `leave_wait` cancels both deferrals and bumps the generation so any in-flight poll is
> discarded by `stale_poll?`. Timeout is the monotonic elapsed check, tripped promptly by the
> timeout `advance`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "wait runtime"`
Expected: PASS (2 examples).

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "inline worker"`
Expected: PASS (1 example).

If a timing test is flaky, increase only the `task.sleep` waits (never the assertions); the poll `delay` and `timeout` values in the test classes are already generous relative to the sleeps.

- [ ] **Step 6: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/task.rb lib/plumbing/operations/dsl.rb spec/plumbing/operations/waits_spec.rb
bundle exec rspec spec/plumbing/operations/waits_spec.rb
git add lib/plumbing/operations/task.rb lib/plumbing/operations/dsl.rb spec/plumbing/operations/waits_spec.rb
git commit -m "feat(operations): wait runtime — polled guards, timeout, generation token, inline guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Interactions

**Files:**
- Modify: `lib/plumbing/operations/dsl.rb` (`interaction`, `.when`, `interaction_states`, `InteractionBuilder`)
- Modify: `lib/plumbing/operations/task.rb` (nothing required beyond Task 2 — the interaction handler is defined by the DSL)
- Test: `spec/plumbing/operations/waits_spec.rb` (add)

**Interfaces:**
- Consumes: `worker.post` (Plan 1 actor), `run_loop` (Task 2), `InvalidState` (Plan 2a).
- Produces:
  - `interaction(name, &body) -> InteractionBuilder`; `InteractionBuilder#when(state) -> Symbol` records the state in which the interaction is valid.
  - calling `op.<name>(*args, **kwargs)` posts an actor message that, in actor context, raises `InvalidState` unless `current_state` matches the `.when` state, else runs the body via `instance_exec` and re-runs `run_loop` (re-evaluating the current wait immediately).

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/waits_spec.rb`, inside the `"Plumbing::Operations wait runtime"` describe block (it already sets up the async worker):

```ruby
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "interaction"`
Expected: FAIL — `undefined method 'interaction'` for the class.

- [ ] **Step 3: Add the interaction DSL**

In `lib/plumbing/operations/dsl.rb`, add inside `module DSL`:

```ruby
      def interaction_states = @interaction_states ||= {}

      def interaction(name, &body)
        name = name.to_sym
        define_method(name) do |*args, **kwargs|
          worker.post(name, args: args, kwargs: kwargs)
        end
        define_method(:"_#{name}") do |args:, kwargs:|
          expected = self.class.interaction_states[name]
          raise Plumbing::Operations::InvalidState, "##{name} cannot run in state #{@current_state.inspect}" unless @current_state == expected
          instance_exec(*args, **kwargs, &body)
          run_loop
        end
        InteractionBuilder.new(self, name)
      end
```

And add the builder class inside `module Operations` (alongside `ActionBuilder`/`DecisionBuilder` in `dsl.rb`):

```ruby
    # Returned by `interaction` so `.when` can record the state the interaction
    # is valid in.
    class InteractionBuilder
      def initialize(klass, name)
        @klass = klass
        @name = name
      end

      def when(state)
        @klass.interaction_states[@name] = state.to_sym
        @name
      end
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "interaction"`
Expected: PASS (2 examples).

> Note: `op.provide_name("Cher")` posts a message; we do not `await` it on the happy path
> (fire-and-forget, like a real caller). The `InvalidState` test `await`s the returned message
> precisely so the in-actor exception surfaces to the caller. The operation's own state is
> untouched by a rejected interaction (the raise happens before `run_loop`).

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/dsl.rb spec/plumbing/operations/waits_spec.rb
bundle exec rspec spec/plumbing/operations/waits_spec.rb
git add lib/plumbing/operations/dsl.rb spec/plumbing/operations/waits_spec.rb
git commit -m "feat(operations): interactions — state-guarded messages that wake a wait

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Restore

**Files:**
- Modify: `lib/plumbing/operations/dsl.rb` (`restore` class method)
- Modify: `lib/plumbing/operations/task.rb` (`resume` private method)
- Test: `spec/plumbing/operations/waits_spec.rb` (add)

**Interfaces:**
- Consumes: `setup_attributes`, `enter_running`'s pieces, `advance`, `@restored_wait_elapsed` (read in `enter_wait`, Task 2).
- Produces:
  - `restore(state:, pipeline: nil, wait_elapsed: 0.0, **attrs) -> Task` — rebuilds the operation at `state` with `attrs` and resumes the loop; `wait_elapsed` (seconds already spent waiting) is applied so a restored wait's `timeout` continues rather than restarting.

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/waits_spec.rb`, inside the `"Plumbing::Operations wait runtime"` describe block:

```ruby
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "restores an operation"`
Expected: FAIL — `undefined method 'restore'` for the class.

- [ ] **Step 3: Add `restore` to the DSL**

In `lib/plumbing/operations/dsl.rb`, add inside `module DSL`:

```ruby
      def restore(state:, pipeline: nil, wait_elapsed: 0.0, **attrs)
        ensure_worker_supports_waits!
        new(pipeline: pipeline).tap { |op| op.__send__(:resume, state.to_sym, attrs, wait_elapsed.to_f) }
      end
```

- [ ] **Step 4: Add `resume` to `Task`**

In `lib/plumbing/operations/task.rb`, add to the `private` section:

```ruby
      def resume(state, attrs, wait_elapsed)
        setup_attributes(attrs)
        @current_state = state
        @status = :running
        @restored_wait_elapsed = wait_elapsed
        worker.call
        advance
      end
```

> `resume` deliberately does NOT emit `Started` (the operation already started in a prior life).
> `@restored_wait_elapsed` is consumed by `enter_wait` (Task 2) to back-date `@wait_started_at`,
> so the restored wait's `timeout` counts from the original entry, not the restore.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/waits_spec.rb -e "restores an operation"`
Expected: PASS (1 example).

- [ ] **Step 6: Run the FULL suite, StandardRB, and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/dsl.rb lib/plumbing/operations/task.rb spec/plumbing/operations/waits_spec.rb
bundle exec rspec
git add lib/plumbing/operations/dsl.rb lib/plumbing/operations/task.rb spec/plumbing/operations/waits_spec.rb
git commit -m "feat(operations): restore — rehydrate an operation into a state, resume the loop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (vs the design's wait/interaction/restore portions):**
- `wait_until` + per-wait `delay`/`timeout` overrides + class defaults → Task 1. ✓
- Non-blocking poll via the worker's `after`; re-evaluate on poll/interaction/external change → Task 2. ✓
- `timeout` measured from entry (monotonic), not reset by polls/interactions → Task 2 (`@wait_started_at` set in `enter_wait`, never in `reschedule_poll`). ✓
- Generation token discards stale polls; one live poll per wait via `cancel_deferred` → Task 2. ✓
- Wait under inline surfaces `NotSupported` (early guard) → Task 2. ✓
- `Waiting` event emitted on wait entry → Tasks 1 (event) + 2 (emit). ✓
- `interaction`/`.when` waking a wait; `InvalidState` in the wrong state; operation state untouched on rejection → Task 3. ✓
- `restore(state:, wait_elapsed:, **attrs)` resuming the loop; timeout continues across restart → Task 4. ✓
- **Deviation noted for the human:** the design described "schedule a poll AND a timeout"; this implements timeout as a deferred `advance` at `timeout` that trips a monotonic elapsed check — same effect, one mechanism. And `restore` takes `wait_elapsed:` (a duration) rather than `wait_started_at:` (an absolute time), because a monotonic clock is not comparable across process restarts. Both are flagged in the plan header.

**2. Placeholder scan:** No TBD/TODO/"handle errors"/"similar to"; every code step shows complete code and exact commands. The full `run_loop` is repeated in Task 2 (not "as Task 2a plus the wait arm") so the engineer transcribes one coherent method. ✓

**3. Type consistency:** `advance(poll_token:)`, `stale_poll?`, `enter_wait`/`reschedule_poll`/`leave_wait`/`timed_out?`/`monotonic`, `@wait_generation`/`@waiting_state`/`@wait_started_at`/`@poll_id`/`@timeout_id`/`@restored_wait_elapsed`, `interaction_states`/`InteractionBuilder#when`, `ensure_worker_supports_waits!`/`has_waits?`, `resume`, and the `Waiting` signature are named identically across the Interfaces blocks and code. The `:wait` arm uses `WaitOptions#delay`/`#timeout` exactly as defined in Plan 2a. ✓

## Notes

- This completes Spec 1. Follow-on specs (separate): Spec 2 (data-file front-end building the same States), Spec 3 (a persistence gem subscribing to the event stream + calling `restore`), Spec 4 (mermaid→Ruby scaffold generator).
- The persistence adapter (Spec 3) computes `wait_elapsed` for `restore` from its own persisted "waiting since" timestamp.
