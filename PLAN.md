# Plumbing v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Plumbing as a `literal`-based toolkit with three concepts — pluggable-worker Actors, a lock-free Service locator, and a composable Event Pipeline — with `literal` as the only runtime dependency.

**Architecture:** Port the `synth_world` `actor` branch as the actor core (composition + a `Worker` base class, not proxies), extend it with a sender *stack* and renamed implementation methods, then build Services (non-actor) and Pipeline (actor-based, immutable `Literal::Data` events with debounced batching) on top. Heavier workers (`async`, `threaded`, `rails`) are opt-in `require`s.

**Tech Stack:** Ruby ≥ 3.2, `literal`, RSpec. Opt-in: `async`, `concurrent-ruby`, `rails`.

**Reference sources (already on disk):**
- New actor to port: `/Volumes/HD/Developer/EchoDek/synth_world` (branch `actor`), `lib/plumbing/actor/*`
- Old workers to port: `/Volumes/HD/Developer/Collabor8Online/plumbing` (branch `main`), `lib/plumbing/actor/threaded.rb`, `actor/rails.rb`, `actor/transporter.rb`
- Old message bus (reference only — being rewritten): `main` `lib/plumbing/pipe*.rb`

See [DESIGN.md](DESIGN.md) for the full specification.

---

## Phase 0 — Foundation (gemspec, version, top-level, types)

### Task 0.1: Reset dependencies and bump version

**Files:**
- Modify: `standard-procedure-plumbing.gemspec`
- Modify: `lib/plumbing/version.rb`

- [ ] **Step 1: Bump the version**

`lib/plumbing/version.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  VERSION = "1.0.0"
end
```

- [ ] **Step 2: Swap the dependency**

In `standard-procedure-plumbing.gemspec`, replace `spec.add_dependency "globalid"` with:
```ruby
  spec.add_dependency "literal"
```
Add `DESIGN.md`, `PLAN.md` to the packaged files glob:
```ruby
    Dir["{lib}/**/*", "Rakefile", "README.md", "DESIGN.md", "PLAN.md", "LICENSE"]
```

- [ ] **Step 3: Add dev dependencies**

In the gemspec (or `Gemfile`), add the opt-in worker gems as development dependencies so the suite can exercise them: `async`, `concurrent-ruby`, `activesupport`.

- [ ] **Step 4: Commit**

```bash
git add standard-procedure-plumbing.gemspec lib/plumbing/version.rb Gemfile
git commit -m "build: v1 deps (literal only) and 1.0.0 version bump"
```

### Task 0.2: Top-level module — Awaitable marker + Kernel#Await

**Files:**
- Modify: `lib/plumbing.rb`
- Create: `lib/plumbing/error.rb` (keep)
- Test: `spec/plumbing/kernel_await_spec.rb` (port from synth_world)

- [ ] **Step 1: Port the await spec**

Copy `spec/plumbing/kernel_await_spec.rb` from synth_world. It asserts: a plain value returns itself; an object including `Plumbing::Awaitable` has its `#await` called and the result returned.

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/plumbing/kernel_await_spec.rb`
Expected: FAIL (`Plumbing::Awaitable` / `Kernel#Await` not defined).

- [ ] **Step 3: Rewrite `lib/plumbing.rb`**

```ruby
# frozen_string_literal: true

require "literal"

module Plumbing
  class Error < StandardError; end

  # Marker for things that can be `await`-ed via Kernel#Await.
  module Awaitable; end
end

require_relative "plumbing/version"
require_relative "plumbing/types"
require_relative "plumbing/object"
require_relative "plumbing/actor"
require_relative "plumbing/services"
require_relative "plumbing/event"
require_relative "plumbing/pipeline"

module Kernel
  def Await(&block)
    result = block.call
    result.is_a?(Plumbing::Awaitable) ? result.await : result
  end
  alias_method :await, :Await
end
```

(Comment out the `require_relative`s for files not yet created; uncomment them as each phase lands.)

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/plumbing/kernel_await_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/plumbing.rb spec/plumbing/kernel_await_spec.rb
git commit -m "feat: Awaitable marker and Kernel#Await"
```

### Task 0.3: Types

**Files:**
- Create: `lib/plumbing/types.rb` (port from synth_world)
- Test: `spec/plumbing/types_spec.rb` (port from synth_world)

- [ ] **Step 1:** Port `spec/plumbing/types_spec.rb` and `lib/plumbing/types.rb` from synth_world verbatim.
- [ ] **Step 2:** Run `bundle exec rspec spec/plumbing/types_spec.rb` — Expected: PASS.
- [ ] **Step 3:** Commit: `git commit -am "feat: literal-based types"`

---

## Phase 1 — `Object#as` + interfaces (replaces RubberDuck)

### Task 1.1: The `as` cast

**Files:**
- Create: `lib/plumbing/object.rb`
- Test: `spec/plumbing/object_as_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/object_as_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe "Object#as" do
  let(:callable) { Literal::Types._Callable }  # built into literal — don't redefine

  it "returns the object itself when it satisfies the interface" do
    duck = ->(x) { x }
    expect(duck.as(callable)).to be(duck)
  end

  it "raises when the object does not satisfy the interface" do
    expect { "not callable".as(callable) }.to raise_error(Literal::TypeError)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/plumbing/object_as_spec.rb`
Expected: FAIL (`undefined method 'as'`).

- [ ] **Step 3: Implement**

`lib/plumbing/object.rb`:
```ruby
# frozen_string_literal: true

class Object
  # Validate this object satisfies the given literal interface/type and
  # return self.  No narrowing proxy — validate-and-passthrough.
  def as(interface)
    Literal.check(self, interface)   # confirmed signature: check(value, type)
    self
  end
end
```

> **Build note:** `Literal.check(value, type)` confirmed against `literal 1.9.0` (positional). Still TODO at this step: probe the exact error class it raises on mismatch and set the `raise_error(...)` expectation to match.

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/plumbing/object_as_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/plumbing/object.rb spec/plumbing/object_as_spec.rb
git commit -m "feat: Object#as interface cast (replaces RubberDuck)"
```

### Task 1.2: Shared interface constants

**Files:**
- Modify: `lib/plumbing/types.rb` (add `Callable`, `Observable`)

- [ ] **Step 1:** `Callable` already ships with literal as `Literal::Types._Callable` — do **not** redefine it. Add only `Observable` to `Plumbing` (in `types.rb`):
```ruby
  Observable = Literal::Types._Interface(:observe, :remove, :remove_all)
```
- [ ] **Step 2:** Commit: `git commit -am "feat: Callable/Observable interfaces"`

---

## Phase 2 — Actor core

Port the synth_world actor, with two changes: the implementation method is renamed `_say` → `_say_implementation` (from `_validated_say_implementation`), and sender tracking becomes a **stack** exposing `current_sender` + `current_senders`.

### Task 2.1: Message + Inline worker + Definitions (port)

**Files:**
- Create: `lib/plumbing/actor.rb`, `lib/plumbing/actor/configuration.rb`, `lib/plumbing/actor/definitions.rb`, `lib/plumbing/actor/worker.rb`, `lib/plumbing/actor/inline.rb`, `lib/plumbing/actor/message.rb`
- Test: `spec/plumbing/actor_spec.rb`, `spec/plumbing/actor_inline_spec.rb` (port from synth_world)

- [ ] **Step 1:** Port the six `lib/plumbing/actor*` files and the two specs from synth_world `actor` branch verbatim as the starting point.
- [ ] **Step 2:** Run `bundle exec rspec spec/plumbing/actor_spec.rb spec/plumbing/actor_inline_spec.rb` — Expected: PASS (baseline behaviour preserved).
- [ ] **Step 3:** Commit: `git commit -am "feat: port synth_world actor core (inline worker)"`

### Task 2.2: Rename implementation method `_validated_NAME_implementation` → `_NAME_implementation`

**Files:**
- Modify: `lib/plumbing/actor/definitions.rb`
- Test: `spec/plumbing/actor_spec.rb`

- [ ] **Step 1: Add a test pinning the method names**

Append to `spec/plumbing/actor_spec.rb`:
```ruby
it "defines say, _say and _say_implementation" do
  klass = Class.new do
    include Plumbing::Actor
    async(:say) { returns { "hi" } }
  end
  expect(klass.instance_methods(false)).to include(:say, :_say, :_say_implementation)
  expect(klass.instance_methods(false)).not_to include(:_validated_say_implementation)
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/plumbing/actor_spec.rb -e "implementation"`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `definitions.rb`, change the implementation method name and the `_NAME` validator's call target:
```ruby
        # internal validator
        define_method :"_#{name}" do |**params, &block|
          validated = method.params_class.new(**params).to_h
          send(:"_#{name}_implementation", **validated, &block)
        end

        # internal implementation
        define_method(:"_#{name}_implementation", &method.implementation)
```
And update `message.rb`'s `implementation` default if it referenced the old name (it derives `:"_#{@method}"`, which is unaffected — verify).

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/plumbing/actor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "refactor: rename actor implementation method to _NAME_implementation"
```

### Task 2.3: Sender stack — `current_sender` + `current_senders`

**Files:**
- Modify: `lib/plumbing/actor.rb`, `lib/plumbing/actor/message.rb`
- Test: `spec/plumbing/actor_sender_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/actor_sender_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe "actor sender tracking" do
  it "exposes the immediate sender and the full chain" do
    inner = Class.new do
      include Plumbing::Actor
      async(:who) { returns { [current_sender, current_senders.dup] } }
    end.new

    middle = Class.new do
      include Plumbing::Actor
      define_method(:peer) { inner }
      async(:call_inner) { returns { await { peer.who(sender: self) } } }
    end
    m = middle.new
    m.define_singleton_method(:peer) { inner }

    immediate, chain = await { m.call_inner(sender: :outer) }
    expect(immediate).to eq(m)          # inner's immediate caller is middle
    expect(chain.first).to eq(:outer)   # outermost first
    expect(chain.last).to eq(m)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/plumbing/actor_sender_spec.rb`
Expected: FAIL (`current_senders` undefined / chain wrong).

- [ ] **Step 3: Implement the stack**

In `lib/plumbing/actor.rb`:
```ruby
    FIBER_KEY = :plumbing_actor_sender_stack

    def current_sender  = (Fiber[FIBER_KEY] || []).last
    def current_senders = (Fiber[FIBER_KEY] || []).dup
```

In `lib/plumbing/actor/message.rb#deliver`, push/pop instead of save/restore:
```ruby
    def deliver
      stack = (Fiber[Plumbing::Actor::FIBER_KEY] ||= [])
      stack.push(@sender)
      @result = @actor.send(@implementation, **@params, &@block)
      @status = :done
    rescue => ex
      @exception = ex
      @status = :error
    ensure
      stack.pop
    end
```

> Note: under the `async` worker each delivery runs in its own fiber, so the fiber-local stack is per-delivery-chain. Confirm the chain is threaded through via the `sender:` argument on each call.

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/plumbing/actor_sender_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: actor current_sender + current_senders (fiber-local stack)"
```

---

## Phase 3 — `async` worker (opt-in)

### Task 3.1: Port the async worker

**Files:**
- Create: `lib/plumbing/actor/async.rb` (port from synth_world)
- Test: `spec/plumbing/actor_async_spec.rb` (port from synth_world)

- [ ] **Step 1:** Port `lib/plumbing/actor/async.rb` and `spec/plumbing/actor_async_spec.rb` from synth_world. The spec must `require "plumbing/actor/async"` and call `Plumbing::Actor.uses :async` (wrapped so it restores `:inline` afterwards).
- [ ] **Step 2:** Confirm the async file self-registers on require:
```ruby
Plumbing::Actor.register(:async) { |actor| Plumbing::Actor::Async.new(actor: actor) }
```
- [ ] **Step 3:** Run `bundle exec rspec spec/plumbing/actor_async_spec.rb` — Expected: PASS.
- [ ] **Step 4:** Commit: `git commit -am "feat: opt-in async actor worker"`

---

## Phase 4 — `threaded` + `rails` workers (opt-in)

Port the 0.x workers onto the new `Worker` base class (`call`/`stop`/`active?`/`dispatch`/`message_class`).

### Task 4.1: Threaded worker

**Files:**
- Create: `lib/plumbing/actor/threaded.rb`, `lib/plumbing/actor/transporter.rb`
- Test: `spec/plumbing/actor_threaded_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/actor_threaded_spec.rb` — mirror the inline/async behavioural specs (send a message, `await` the result, assert it ran off the calling thread). Wrap in `require "plumbing/actor/threaded"` + `Plumbing::Actor.uses :threaded` with restore.

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (no `:threaded` worker registered).

- [ ] **Step 3: Implement** — Subclass `Plumbing::Actor::Worker`:
  - hold a `Concurrent::Array` queue + a `Thread::Mutex` (from 0.x `threaded.rb`)
  - `dispatch(message)` enqueues then schedules a drain on the actor thread (`Concurrent::ScheduledTask` + `@mutex.synchronize`)
  - `active?`/`stop` per the base contract
  - `message_class` returns a `Threaded::Message < Actor::Message` whose `_wait_until_ready` blocks on a `Concurrent::MVar`
  - port `Transporter` from 0.x **only if** cross-thread arg marshalling is required; otherwise pass args by reference and note the thread-safety caveat in DESIGN.md. If kept, add `globalid` as a *threaded-only* optional dependency.
  - self-register: `Plumbing::Actor.register(:threaded) { |actor| Threaded.new(actor: actor) }`

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -am "feat: opt-in threaded actor worker"`

### Task 4.2: Rails worker

**Files:**
- Create: `lib/plumbing/actor/rails.rb`
- Test: `spec/plumbing/actor_rails_spec.rb`

- [ ] **Step 1:** Write a spec mirroring threaded, but asserting work runs inside `Rails.application.executor.wrap` (or `ActiveSupport::Executor`). Skip the spec unless `activesupport` is loadable.
- [ ] **Step 2:** Run — Expected: FAIL.
- [ ] **Step 3:** Implement `Rails < Threaded`, wrapping the drain in the ActiveSupport executor (port the wrapping from 0.x `actor/rails.rb`). Self-register `:rails`.
- [ ] **Step 4:** Run — Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "feat: opt-in rails-safe actor worker"`

---

## Phase 5 — Services (service locator)

### Task 5.1: Registry with singleton + factory

**Files:**
- Create: `lib/plumbing/services.rb`
- Modify: `lib/plumbing.rb` (add `Plumbing.services` global)
- Test: `spec/plumbing/services_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/services_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Plumbing::Services do
  subject(:services) { described_class.new }

  it "returns an eagerly-registered singleton object" do
    obj = Object.new
    services.register(:thing, obj)
    expect(services[:thing]).to be(obj)
  end

  it "builds a lazy singleton once, on first access" do
    calls = 0
    services.register(:db) { calls += 1; Object.new }
    a = services[:db]
    b = services[:db]
    expect(a).to be(b)
    expect(calls).to eq(1)
  end

  it "builds a fresh object every access via create" do
    services.create(:clock) { Object.new }
    expect(services[:clock]).not_to be(services[:clock])
  end

  it "aliases singleton->register and factory->create" do
    expect(services.method(:singleton).original_name).to eq(:register)
    expect(services.method(:factory).original_name).to eq(:create)
  end

  it "rejects ambiguous registration" do
    expect { services.register(:x, Object.new) { Object.new } }.to raise_error(ArgumentError)
    expect { services.register(:x) }.to raise_error(ArgumentError)
  end

  it "raises a clear error for an unknown service" do
    expect { services[:missing] }.to raise_error(KeyError)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/plumbing/services_spec.rb`
Expected: FAIL (`Plumbing::Services` not defined).

- [ ] **Step 3: Implement**

`lib/plumbing/services.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  # A lock-free, prefilled-at-boot service locator.
  class Services
    Singleton = Struct.new(:builder, :value, :built) do
      def resolve
        return value if built
        self.value = builder.call
        self.built = true
        value
      end
    end
    private_constant :Singleton

    def initialize
      @entries = {}
    end

    # Same object every time.  Eager when given `object`, lazy when given a block.
    def register(name, object = nil, &builder)
      raise ArgumentError, "supply exactly one of object/builder" unless object.nil? ^ builder.nil?
      @entries[name.to_sym] = object.nil? ? Singleton.new(builder, nil, false) : Singleton.new(nil, object, true)
      name.to_sym
    end
    alias_method :singleton, :register

    # Fresh object on every access.
    def create(name, &builder)
      raise ArgumentError, "create requires a block" if builder.nil?
      @entries[name.to_sym] = builder
      name.to_sym
    end
    alias_method :factory, :create

    def [](name)
      entry = @entries.fetch(name.to_sym)
      entry.is_a?(Singleton) ? entry.resolve : entry.call
    end
  end

  def self.services
    @services ||= Services.new
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/plumbing/services_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/plumbing/services.rb lib/plumbing.rb spec/plumbing/services_spec.rb
git commit -m "feat: lock-free service locator (register/create + singleton/factory aliases)"
```

---

## Phase 6 — Event + Pipeline

### Task 6.1: Event base + registry

**Files:**
- Create: `lib/plumbing/event.rb`
- Test: `spec/plumbing/event_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/event_spec.rb`:
```ruby
require "spec_helper"

class ThingHappened < Plumbing::Event
  prop :id, String
end

RSpec.describe Plumbing::Event do
  it "is value-equal and hashes on its props" do
    a = ThingHappened.new(id: "1")
    b = ThingHappened.new(id: "1")
    expect(a).to eq(b)
    expect(Set.new([a, b]).size).to eq(1)
  end

  it "is frozen / immutable" do
    expect(ThingHappened.new(id: "1")).to be_frozen
  end
end
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (`Plumbing::Event` not defined).

- [ ] **Step 3: Implement**

`lib/plumbing/event.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  class Event < Literal::Data
  end
end
```
(Confirm `Literal::Data` freezes instances and gives prop-based `==`/`hash`; per the literal docs both `Literal::Object` and `Literal::Data` hash on their properties.)

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -am "feat: immutable Plumbing::Event base"`

### Task 6.2: Pipeline::Base (actor) — observe/remove/push with debounced batching

**Files:**
- Create: `lib/plumbing/pipeline.rb`, `lib/plumbing/pipeline/base.rb`, `lib/plumbing/pipeline/source.rb`
- Test: `spec/plumbing/pipeline_source_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/plumbing/pipeline_source_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Plumbing::Pipeline::Source do
  it "notifies observers of pushed events" do
    received = []
    source = described_class.new
    source.observe { |event| received << event }
    await { source.push(ThingHappened.new(id: "1")) }
    expect(received.map(&:id)).to eq(["1"])
  end

  it "debounces duplicate events within a batch" do
    received = []
    source = described_class.new
    source.observe { |event| received << event }
    await { source.push(ThingHappened.new(id: "1")) }
    await { source.push(ThingHappened.new(id: "1")) } # value-equal => debounced
    expect(received.size).to eq(1)
  end

  it "removes observers" do
    received = []
    source = described_class.new
    observer = ->(event) { received << event }
    source.observe(&observer)
    source.remove(observer)
    await { source.push(ThingHappened.new(id: "1")) }
    expect(received).to be_empty
  end
end
```
(Reuses `ThingHappened` from `event_spec.rb`; define it in a shared support file if specs run in isolation.)

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement `Pipeline::Base`**

`lib/plumbing/pipeline/base.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  class Pipeline
    class Base
      include Plumbing::Actor

      def initialize = (@observers = []; @queue = []; @seen = Set.new)

      async :observe do
        param :observer, Proc
        returns { @observers << observer; observer }
      end

      async :remove do
        param :observer, Proc
        returns { @observers.delete(observer) }
      end

      async :remove_all do
        returns { @observers.clear }
      end

      async :push do
        param :event, Plumbing::Event           # _Descendant(Plumbing::Event) — refine to the literal type
        param :debounce, _Boolean, default: true
        returns do
          if debounce
            @queue << event if @seen.add?(event)  # Set#add? => nil if already queued
          else
            @queue << event                       # forced through, even if a dup
          end
          await { send(:notify_observers, sender: self) }
          event
        end
      end

      async :notify_observers do
        returns do
          batch = @queue
          @queue = []
          @seen.clear
          batch.each { |event| @observers.each { |observer| observer.call(event) } }
        end
      end
    end
  end
end
```

> Build notes: (1) tighten `param :event` to the literal descendant type once the `as`/types API is confirmed; (2) debounce uses a `Set` (`@seen`) as an O(1) dedup index via `Set#add?`, while the ordered `@queue` Array preserves emission order and lets `debounce: false` push an intentional dup through — `require "set"` at the top (core in Ruby 4, but keep the require for the gem's `>= 3.2` floor); (3) `push` triggers a single async `notify_observers` pass so a burst coalesces into one drain.

`lib/plumbing/pipeline/source.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  class Pipeline
    class Source < Base
    end
  end
end
```

`lib/plumbing/pipeline.rb`:
```ruby
# frozen_string_literal: true

require_relative "pipeline/base"
require_relative "pipeline/source"
require_relative "pipeline/only"
require_relative "pipeline/except"
require_relative "pipeline/filter"
require_relative "pipeline/junction"

module Plumbing
  class Pipeline
    @event_types = {}

    def self.register(klass)
      klass.as(Literal::Types._Descendant(Plumbing::Event)) # validate
      @event_types[klass.name] = klass
    end

    def self.event_type(name) = @event_types.fetch(name)
  end
end
```

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -am "feat: Pipeline::Base + Source with debounced batching"`

### Task 6.3: notify (build registered event by type name)

**Files:**
- Modify: `lib/plumbing/pipeline/base.rb`
- Test: `spec/plumbing/pipeline_notify_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "spec_helper"

RSpec.describe "Pipeline#notify" do
  it "builds a registered event from its type name and emits it" do
    Plumbing::Pipeline.register(ThingHappened)
    received = []
    source = Plumbing::Pipeline::Source.new
    source.observe { |event| received << event }
    await { source.notify("ThingHappened", id: "1") }
    expect(received.first).to eq(ThingHappened.new(id: "1"))
  end
end
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (`notify` undefined).

- [ ] **Step 3: Implement** — add to `Pipeline::Base`:
```ruby
      async :notify do
        param :event_type, String
        param :debounce, _Boolean, default: true
        param :params, _Hash?, default: {}.freeze
        returns do
          event = Plumbing::Pipeline.event_type(event_type).new(**params)
          await { send(:push, event: event, debounce: debounce, sender: self) }
        end
      end
```

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -am "feat: Pipeline#notify builds registered events"`

### Task 6.4: Composition — Only, Except, Filter, Junction

**Files:**
- Create: `lib/plumbing/pipeline/only.rb`, `except.rb`, `filter.rb`, `junction.rb`
- Test: `spec/plumbing/pipeline_composition_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "spec_helper"

class ErrorRaised < Plumbing::Event; prop :id, String; end
class InfoLogged  < Plumbing::Event; prop :id, String; end

RSpec.describe "Pipeline composition" do
  def collect(pipeline)
    out = []
    pipeline.observe { |e| out << e.class.name }
    out
  end

  it "Only emits matching event-types (with wildcards)" do
    src = Plumbing::Pipeline::Source.new
    only = Plumbing::Pipeline::Only.new(source: src, filters: ["Error*"])
    out = collect(only)
    await { src.push(ErrorRaised.new(id: "1")) }
    await { src.push(InfoLogged.new(id: "2")) }
    expect(out).to eq(["ErrorRaised"])
  end

  it "Except emits everything but the matches" do
    src = Plumbing::Pipeline::Source.new
    except = Plumbing::Pipeline::Except.new(source: src, filters: ["Error*"])
    out = collect(except)
    await { src.push(ErrorRaised.new(id: "1")) }
    await { src.push(InfoLogged.new(id: "2")) }
    expect(out).to eq(["InfoLogged"])
  end

  it "Filter matches by regexp" do
    src = Plumbing::Pipeline::Source.new
    filter = Plumbing::Pipeline::Filter.new(source: src, filters: [/Error/])
    out = collect(filter)
    await { src.push(ErrorRaised.new(id: "1")) }
    expect(out).to eq(["ErrorRaised"])
  end

  it "Junction merges multiple sources" do
    a = Plumbing::Pipeline::Source.new
    b = Plumbing::Pipeline::Source.new
    junction = Plumbing::Pipeline::Junction.new(a, b)
    out = collect(junction)
    await { a.push(ErrorRaised.new(id: "1")) }
    await { b.push(InfoLogged.new(id: "2")) }
    expect(out.sort).to eq(["ErrorRaised", "InfoLogged"])
  end
end
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement** — each filtering pipeline observes its `source` and re-pushes what passes. Wildcard matching converts `"Error*"` → a prefix test on `event.class.name`.

`lib/plumbing/pipeline/only.rb`:
```ruby
# frozen_string_literal: true

module Plumbing
  class Pipeline
    class Only < Base
      def initialize(source:, *filters)
        super()
        @filters = filters
        source.as(Plumbing::Observable)
        @forwarder = ->(event) { await { push(event: event) } if matches?(event) }
        source.observe(&@forwarder)
      end

      private

      def matches?(event)
        name = event.class.name
        @filters.any? { |f| f.end_with?("*") ? name.start_with?(f[0..-2]) : name == f }
      end
    end
  end
end
```
(`Except` is `Only` with `!matches?`; `Filter` uses `@filters.any? { |re| re.match?(name) }` over `Regexp`s; `Junction` takes `*sources` and observes each, forwarding everything.) Keep the constructor signatures aligned with DESIGN.md (`filters:` splat for Only/Except/Filter, `sources` splat for Junction).

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit:** `git commit -am "feat: Pipeline Only/Except/Filter/Junction composition"`

---

## Phase 7 — Test helpers, changelog, cleanup

### Task 7.1: Worker test helper

**Files:**
- Create: `lib/plumbing/spec/workers.rb`
- Test: used by the suite

- [ ] **Step 1:** Provide a helper that runs a block under each available worker and restores `:inline` afterwards (the v1 replacement for the old `Plumbing::Spec.modes`). Yield the worker name to the block.
- [ ] **Step 2:** Convert at least the actor behavioural specs to run under every installed worker via the helper.
- [ ] **Step 3:** Run `bundle exec rspec` — Expected: full suite PASS.
- [ ] **Step 4:** Commit: `git commit -am "test: run actor specs under every worker"`

### Task 7.2: Remove dead 0.x code + changelog

**Files:**
- Delete: `lib/plumbing/rubber_duck*`, `lib/plumbing/pipe*`, old `lib/plumbing/pipeline.rb` operations code, `lib/plumbing/config.rb` (if fully superseded), old `actor/kernel.rb`/`actor/async.rb`(0.x)/`actor/transporter.rb`(if unused)
- Create: `CHANGELOG.md` (0.x → 1.0 migration notes)

- [ ] **Step 1:** Delete superseded files; run `bundle exec rspec` to confirm nothing references them — Expected: PASS.
- [ ] **Step 2:** Write `CHANGELOG.md`: the four breaking changes (Pipeline rename, RubberDuck removal, operations-Pipeline removal, worker-selection API) + a short migration snippet for each.
- [ ] **Step 3:** Run `bundle exec standardrb --fix` (project uses standard) then `bundle exec rspec`.
- [ ] **Step 4:** Commit: `git commit -am "chore: remove 0.x code, add 1.0 changelog + migration notes"`

---

## Self-review notes (spec coverage)

- `Object#as` → Task 1.1; `Callable`/`Observable` → 1.2.
- Actor (typed params, three renamed methods, pluggable workers, sender stack) → Phase 2–4.
- Dependency policy (literal-only core; async/threaded/rails opt-in self-registering) → Tasks 0.1, 3.1, 4.1, 4.2.
- Services (singleton eager+lazy, factory, register/create aliases, validation, sync reads) → Task 5.1.
- Event (Literal::Data, value equality, hash, registry) → 6.1, registry in 6.2.
- Pipeline (push/`<<`, notify, observe/remove/remove_all, debounce+batching, Base/Source/Only/Except/Filter/Junction) → 6.2–6.4. **Gap to wire during 6.2:** add `alias_method :<<, :push` on the proxy/exposed method.
- Open items (literal `check` arg order, threaded marshalling/globalid, test helpers, changelog) tracked in DESIGN.md and Phase 4/7.
