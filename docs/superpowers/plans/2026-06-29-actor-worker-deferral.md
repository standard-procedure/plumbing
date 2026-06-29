# Actor Worker Deferral Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deferred message delivery (`after` / `cancel_deferred`) to the Plumbing actor worker contract, so an actor can ask its worker to deliver a message to itself after a delay, and cancel it race-safely.

**Architecture:** A new `Plumbing::Actor::Deferral` handle carries a mutex-guarded cancelled flag. The `Worker` base gains an `after` (raises `NotImplementedError`) and a shared `cancel_deferred`. Each worker implements `after` in its own idiom: inline raises `Plumbing::Actor::NotSupported`; async spawns a transient `Async` task that sleeps then dispatches; threaded spawns a timer thread that sleeps then enqueues. The `Plumbing::Actor` module exposes `after`/`cancel_deferred` instance methods that delegate to the worker. Deferred delivery reuses the normal `dispatch` path, preserving the one-at-a-time actor ordering guarantee.

**Tech Stack:** Ruby 4.x, Literal (`Literal::Data` workers), the `async` gem (opt-in worker), RSpec, StandardRB.

This is **Plan 1 of 2** for Spec 1 (`Plumbing::Operations`). It is a self-contained, independently useful actor capability. Plan 2 (the operations engine) builds on it.

## Global Constraints

- `# frozen_string_literal: true` at the top of every Ruby file.
- StandardRB must be clean: run `bundle exec standardrb --fix <files>` before every commit.
- Workers are **frozen** `Literal::Data` — never assign instance variables on a worker after construction; mutable state lives in its own object (here, the `Deferral`).
- The actor ordering guarantee is sacred: deferred messages must be delivered through the worker's normal `dispatch`, never delivered inline out of band.
- The `async` and `threaded` workers are **opt-in requires** (`require "plumbing/actor/async"` / `"plumbing/actor/threaded"`); the async worker also needs `require "async"`. Async actors run inside `Sync do |task| … end` and must be woken with `task.sleep` (a bare `sleep` blocks the reactor).
- Worker selection is **global**: `Plumbing::Actor.uses :async` then reset with `Plumbing::Actor.uses :inline` in an `after` hook.
- Test command: `bundle exec rspec <path>`.
- Work on the `operation-spec` branch (already checked out). Do not push to `main`.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

```
lib/plumbing/actor/deferral.rb     # NEW — Deferral handle (mutex-guarded cancelled flag)
lib/plumbing/actor/worker.rb       # MOD — require deferral; base #after (NotImplementedError) + #cancel_deferred
lib/plumbing/actor.rb              # MOD — NotSupported error; #after / #cancel_deferred delegators
lib/plumbing/actor/inline.rb       # MOD — #after raises NotSupported
lib/plumbing/actor/async.rb        # MOD — #after via a transient Async task
lib/plumbing/actor/threaded.rb     # MOD — #after via a timer thread
spec/plumbing/actor_deferral_spec.rb  # NEW — Deferral unit + inline/async/threaded behaviour
```

---

### Task 1: Deferral handle, worker contract, inline raises

**Files:**
- Create: `lib/plumbing/actor/deferral.rb`
- Modify: `lib/plumbing/actor/worker.rb` (add require + two methods)
- Modify: `lib/plumbing/actor.rb` (add `NotSupported` + delegators)
- Modify: `lib/plumbing/actor/inline.rb` (override `after`)
- Test: `spec/plumbing/actor_deferral_spec.rb` (create)

**Interfaces:**
- Produces:
  - `Plumbing::Actor::Deferral#cancel -> true`, `#cancelled? -> Boolean`
  - `Plumbing::Actor::NotSupported < StandardError`
  - `Plumbing::Actor#after(delay, call:, sender: nil, **params, &block) -> Deferral` (delegates to `worker.after`)
  - `Plumbing::Actor#cancel_deferred(deferral) -> void`
  - `Plumbing::Actor::Worker#after(delay, method:, sender: nil, params: {}, block: nil) -> Deferral` (base raises `NotImplementedError`)
  - `Plumbing::Actor::Worker#cancel_deferred(deferral) -> void` (calls `deferral&.cancel`)

- [ ] **Step 1: Write the failing Deferral unit test**

Create `spec/plumbing/actor_deferral_spec.rb`:

```ruby
# frozen_string_literal: true

require "plumbing/actor/async"
require "plumbing/actor/threaded"
require "async"

RSpec.describe "Actor deferral" do
  describe Plumbing::Actor::Deferral do
    it "starts uncancelled and flips when cancelled" do
      deferral = described_class.new
      expect(deferral.cancelled?).to be false
      deferral.cancel
      expect(deferral.cancelled?).to be true
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb`
Expected: FAIL — `uninitialized constant Plumbing::Actor::Deferral`.

- [ ] **Step 3: Implement Deferral**

Create `lib/plumbing/actor/deferral.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Actor
    # An opaque handle for a scheduled (deferred) message. Cancelling sets a
    # flag that the worker's timer checks before dispatching, so a timer that
    # fires concurrently with a cancel simply does nothing (race-safe).
    class Deferral
      def initialize
        @lock = Mutex.new
        @cancelled = false
      end

      def cancel = @lock.synchronize { @cancelled = true }

      def cancelled? = @lock.synchronize { @cancelled }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb`
Expected: PASS (1 example).

- [ ] **Step 5: Write the failing inline-raises test**

Add inside the top-level `describe "Actor deferral" do … end` block in `spec/plumbing/actor_deferral_spec.rb`:

```ruby
  describe "inline worker" do
    before { Plumbing::Actor.uses :inline }

    let(:actor_class) do
      Class.new do
        include Plumbing::Actor
        async(:noop) { returns { :ok } }
      end
    end

    it "raises NotSupported because there is no loop to deliver a later message" do
      actor = actor_class.new
      expect { actor.after(0.01, call: :noop) }.to raise_error(Plumbing::Actor::NotSupported)
    end
  end
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb -e "inline worker"`
Expected: FAIL — `NoMethodError: undefined method 'after'` for the actor (delegator not defined yet).

- [ ] **Step 7: Add the require and base contract to the Worker**

In `lib/plumbing/actor/worker.rb`, add the require near the top (after the existing `require_relative "message"`):

```ruby
require_relative "deferral"
```

Then add these two methods to the `Worker` class body (e.g. directly after `def post …`):

```ruby
      # Deliver `method` to this actor after `delay` seconds. Returns a Deferral
      # handle. Base raises; each worker implements its own timer.
      def after(delay, method:, sender: nil, params: {}, block: nil) = raise NotImplementedError

      # Cancel a previously-scheduled deferral (race-safe no-op flag).
      def cancel_deferred(deferral) = deferral&.cancel
```

- [ ] **Step 8: Add NotSupported and the actor delegators**

In `lib/plumbing/actor.rb`, inside `module Plumbing; module Actor`, add the error constant just below `FIBER_KEY`:

```ruby
    # Raised when an actor asks for a capability its worker cannot provide
    # (e.g. deferring a message on the inline worker).
    NotSupported = Class.new(StandardError)
```

And add these two instance methods to the `Plumbing::Actor` module (e.g. after `current_senders`):

```ruby
    # Ask the worker to deliver `call` to this actor after `delay` seconds.
    # Returns a Plumbing::Actor::Deferral that can be passed to cancel_deferred.
    def after(delay, call:, sender: nil, **params, &block)
      worker.after(delay, method: call, sender: sender, params: params, block: block)
    end

    # Cancel a deferral returned by #after.
    def cancel_deferred(deferral) = worker.cancel_deferred(deferral)
```

- [ ] **Step 9: Make the inline worker raise NotSupported**

In `lib/plumbing/actor/inline.rb`, add to the `Inline` class body (e.g. after `def stop = nil`):

```ruby
      def after(*, **) = raise Plumbing::Actor::NotSupported, "the inline worker cannot defer messages; use :async or :threaded"
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb`
Expected: PASS (2 examples — Deferral unit + inline raises).

- [ ] **Step 11: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/actor/deferral.rb lib/plumbing/actor/worker.rb lib/plumbing/actor.rb lib/plumbing/actor/inline.rb spec/plumbing/actor_deferral_spec.rb
bundle exec rspec spec/plumbing/actor_deferral_spec.rb
git add lib/plumbing/actor/deferral.rb lib/plumbing/actor/worker.rb lib/plumbing/actor.rb lib/plumbing/actor/inline.rb spec/plumbing/actor_deferral_spec.rb
git commit -m "feat(actor): deferral handle + worker after/cancel_deferred contract (inline raises)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Async worker `after`

**Files:**
- Modify: `lib/plumbing/actor/async.rb` (add `after`)
- Test: `spec/plumbing/actor_deferral_spec.rb` (add an async context)

**Interfaces:**
- Consumes: `Plumbing::Actor::Deferral`, `Worker#build_message`, `Async#dispatch` (enqueue), `Plumbing::Actor#after`/`#cancel_deferred` (Task 1).
- Produces: `Plumbing::Actor::Async#after(delay, method:, sender: nil, params: {}, block: nil) -> Deferral` that dispatches the built message after `delay` unless cancelled.

- [ ] **Step 1: Write the failing async delivery + cancel tests**

Add inside the top-level `describe "Actor deferral" do … end` block in `spec/plumbing/actor_deferral_spec.rb`:

```ruby
  describe "async worker" do
    before { Plumbing::Actor.uses :async }
    after { Plumbing::Actor.uses :inline }

    let(:counter_class) do
      Class.new do
        include Plumbing::Actor
        async(:tick) { returns { @count = (@count || 0) + 1 } }
        async(:count) { returns { @count || 0 } }
      end
    end

    it "delivers a deferred message after the delay" do
      Sync do |task|
        counter = counter_class.new
        counter.worker.call
        counter.after(0.05, call: :tick)
        task.sleep 0.15
        expect(counter.count.await).to eq 1
      end
    end

    it "does not deliver a cancelled deferred message" do
      Sync do |task|
        counter = counter_class.new
        counter.worker.call
        deferral = counter.after(0.05, call: :tick)
        counter.cancel_deferred(deferral)
        task.sleep 0.15
        expect(counter.count.await).to eq 0
      end
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb -e "async worker"`
Expected: FAIL — `NotImplementedError` raised from `Worker#after` (the Async worker has not overridden it).

- [ ] **Step 3: Implement async `after`**

In `lib/plumbing/actor/async.rb`, add to the `Async` class body (e.g. after `def dispatch(message) = @queue.enqueue(message)`):

```ruby
      def after(delay, method:, sender: nil, params: {}, block: nil)
        message = build_message(method: method, sender: sender, params: params, block: block)
        deferral = Plumbing::Actor::Deferral.new
        Kernel.Async(transient: true) do |task|
          task.sleep delay
          dispatch(message) unless deferral.cancelled?
        end
        deferral
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb -e "async worker"`
Expected: PASS (2 examples).

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/actor/async.rb spec/plumbing/actor_deferral_spec.rb
bundle exec rspec spec/plumbing/actor_deferral_spec.rb
git add lib/plumbing/actor/async.rb spec/plumbing/actor_deferral_spec.rb
git commit -m "feat(actor): async worker after — deferred dispatch via a transient Async task

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Threaded worker `after`

**Files:**
- Modify: `lib/plumbing/actor/threaded.rb` (add `after`)
- Test: `spec/plumbing/actor_deferral_spec.rb` (add a threaded context)

**Interfaces:**
- Consumes: `Plumbing::Actor::Deferral`, `Worker#build_message`, `Threaded#call` (ensures the consumer thread), `Threaded#dispatch` (enqueue), `Plumbing::Actor#after`/`#cancel_deferred` (Task 1).
- Produces: `Plumbing::Actor::Threaded#after(delay, method:, sender: nil, params: {}, block: nil) -> Deferral` that enqueues the built message after `delay` unless cancelled.

- [ ] **Step 1: Write the failing threaded delivery + cancel tests**

Add inside the top-level `describe "Actor deferral" do … end` block in `spec/plumbing/actor_deferral_spec.rb`:

```ruby
  describe "threaded worker" do
    before { Plumbing::Actor.uses :threaded }
    after { Plumbing::Actor.uses :inline }

    let(:counter_class) do
      Class.new do
        include Plumbing::Actor
        async(:tick) { returns { @count = (@count || 0) + 1 } }
        async(:count) { returns { @count || 0 } }
      end
    end

    it "delivers a deferred message after the delay" do
      counter = counter_class.new
      counter.after(0.05, call: :tick)
      sleep 0.2
      expect(counter.count.await).to eq 1
    end

    it "does not deliver a cancelled deferred message" do
      counter = counter_class.new
      deferral = counter.after(0.05, call: :tick)
      counter.cancel_deferred(deferral)
      sleep 0.2
      expect(counter.count.await).to eq 0
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb -e "threaded worker"`
Expected: FAIL — `NotImplementedError` raised from `Worker#after` (the Threaded worker has not overridden it).

- [ ] **Step 3: Implement threaded `after`**

In `lib/plumbing/actor/threaded.rb`, add to the `Threaded` class body (e.g. after `def dispatch(message) … end`, before `private`):

```ruby
      def after(delay, method:, sender: nil, params: {}, block: nil)
        call
        message = build_message(method: method, sender: sender, params: params, block: block)
        deferral = Plumbing::Actor::Deferral.new
        Thread.new do
          sleep delay
          dispatch(message) unless deferral.cancelled?
        end
        deferral
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/plumbing/actor_deferral_spec.rb -e "threaded worker"`
Expected: PASS (2 examples).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bundle exec rspec`
Expected: PASS — all pre-existing examples plus the 6 new deferral examples.

- [ ] **Step 6: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/actor/threaded.rb spec/plumbing/actor_deferral_spec.rb
bundle exec rspec
git add lib/plumbing/actor/threaded.rb spec/plumbing/actor_deferral_spec.rb
git commit -m "feat(actor): threaded worker after — deferred dispatch via a timer thread

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes for Plan 2 (operations engine)

- **Worker selection is global by design — do not add per-class selection.**
  `Plumbing::Actor.uses` sets one worker type for the whole process at startup. This is
  intentional: a Rails app must use the threaded worker (threads would clash otherwise) and a
  fibre-based async worker can starve the DB connection pool unless the whole app is
  fibre-aware. Operations do not select a worker. A wait under the inline worker already
  surfaces `Plumbing::Actor::NotSupported` via `after` (Task 1); Plan 2 may add an explicit
  early guard for a friendlier message, nothing more.
- The operations engine should expose its loop step as a normal async method (e.g.
  `async :advance`) so `after(delay, call: :advance, token:)` delivers through the standard
  validated path — do not point `after` at a raw `_`-prefixed internal method.

## Self-Review

**1. Spec coverage (vs the "Deferral as a worker capability" section of the design):**
- `after(seconds, call:, **params)` returning an id → Task 1 (delegator) + Tasks 2/3 (real timers). ✓
- `cancel_deferred(id)` as a race-safe no-op flag → Task 1 (`Deferral`, `cancel_deferred`) + verified in Tasks 2/3 cancel tests. ✓
- inline raises `NotSupported` → Task 1. ✓
- async → transient `Async` task that sleeps then dispatches → Task 2. ✓
- threaded → timer thread that sleeps then enqueues → Task 3. ✓
- workers are frozen `Literal::Data`; mutable state in its own object → satisfied (state lives in `Deferral`, not the worker). ✓
- ordering preserved (dispatch through the normal queue) → async `dispatch` enqueues, threaded `dispatch` enqueues. ✓
- rails durable `after` → explicitly future/out of scope (design "Open questions"); not in this plan. ✓ (intentional)

**2. Placeholder scan:** no TBD/TODO/"handle errors"/"similar to"; every code step shows complete code and exact commands. ✓

**3. Type consistency:** `Deferral#cancel`/`#cancelled?`, `Worker#after(delay, method:, sender:, params:, block:)`, `Actor#after(delay, call:, sender:, **params, &block)`, `Actor#cancel_deferred(deferral)`, `NotSupported` — names and signatures identical across Tasks 1–3 and the Interfaces blocks. ✓
