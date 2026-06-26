# Plumbing v1 — Design

**Status:** Approved, building on the `v1` branch. Breaking rewrite, `0.5.2 → 1.0.0`.

## Why

Plumbing exists to be a *small, fast* toolkit for the handful of concurrency
patterns a Ruby app actually needs — actors, a service registry and a
composable event stream — without the surface area and ceremony of the
`dry-*` family. v1 keeps that "simpler than the alternatives" promise but
rebases the whole gem on [`literal`](https://github.com/joeldrapper/literal):
typed props, parameter contracts and interface checks come essentially for
free, and `literal` is itself small and fast, so it doesn't compromise the
ethos.

## Dependency policy

**The core gem depends on `literal` and nothing else.**

Everything that pulls in a heavier dependency is opt-in: the consumer must
`require` it explicitly *and* add the underlying gem to their own Gemfile.

| Worker / feature | Extra `require` | Gem the app must add |
|---|---|---|
| `inline` actor worker | — (always loaded, the default) | — |
| `async` actor worker | `plumbing/actor/async` | `async` |
| `threaded` actor worker | `plumbing/actor/threaded` | — (core Ruby `Thread`/`Queue`) |
| `rails` actor worker | `plumbing/actor/rails` | `rails` (ActiveSupport) |

This is why `globalid` is dropped from the gemspec — the old `Transporter`
(cross-thread arg marshalling) belongs with the opt-in `threaded` worker, not
the core.

## Breaking changes from 0.x

- `Plumbing::Pipeline` (sequential operations) is **removed** — a better
  version is brewing elsewhere.
- `Plumbing::Pipe` (the message bus) is **renamed to `Plumbing::Pipeline`**
  and rewritten around `Literal::Data` events. Anyone on the old
  `Plumbing::Pipeline` API breaks loudly; this is a major-version bump,
  documented in the migration notes.
- `Plumbing::RubberDuck` is **removed**; `literal`'s `_Interface` replaces it.
  The global `Object#as` is **kept** (see below).
- Actors are rebuilt on the new worker model (no more dynamically-built
  proxy classes). Worker selection moves from the global `Plumbing.config
  mode:` to `Plumbing::Actor.uses :worker_name`.

## The v1 surface

Four concepts: **Actor**, **Services**, **Pipeline/Event**, plus the
`Object#as` cast and `literal`'s types.

---

### 1. `Object#as` (the only survivor of RubberDuck)

A global cast that validates an object satisfies an interface and returns the
object itself (no narrowing proxy — that behaviour is intentionally dropped):

```ruby
class Object
  def as(interface)
    Literal.check(self, interface)   # check(value, type) — confirmed against literal 1.9.0
    self
  end
end

# `Callable` already ships with literal as `Literal::Types._Callable` — use it
# directly, don't redefine. Only `Observable` is ours:
Observable = Literal::Types._Interface(:observe, :remove, :remove_all)
```

Trade-off vs 0.x: callers can still reach non-interface methods afterwards.
We're choosing validate-and-passthrough over enforcement-by-narrowing
(drops `rubber_duck/proxy.rb` entirely).

---

### 2. Actor

Carried over from the `synth_world` `actor` branch, then extended.

- `include Plumbing::Actor`; each actor **owns a `@worker`** (composition),
  built at `initialize` from the selected worker type.
- The `async` DSL carries typed parameter contracts inline and generates
  three methods (renamed from the synth_world prototype):
  - `say` — external; posts a `Message` to the worker, returns the awaitable `Message`
  - `_say` — internal; validates params via the generated `literal` params class
  - `_say_implementation` — internal; the actual body
- Calling an async method returns an `Awaitable` `Message`; resolve with
  `.await` or `await { actor.say(...) }`.

```ruby
class Greeting
  include Plumbing::Actor
  def initialize(name:) = @name = name

  async :say do
    param :greeting, String, default: "Hello"
    # Validated params are passed into the `returns` block as keyword parameters
    # — declare them with `|greeting:|` and they arrive as plain, type-checked
    # locals, used alongside the instance's own @name.
    returns { |greeting:| "#{greeting} #{@name}" }
  end
end

g = Greeting.new(name: "Alice")
await { g.say(greeting: "Hi") }   # => "Hi Alice"
```

#### Sender tracking

Each delivery records its sender on a **fiber-local stack** (push in
`Message#deliver`, pop in `ensure`):

- `current_sender`  — the immediate caller (top of stack), or `nil`
- `current_senders` — the full call-chain, outermost → innermost

(The synth_world prototype only save/restores a single value; v1 makes it a
stack to expose the chain.)

#### Workers

A `Worker` base class (`literal`) defines the extension point —
`call`/`stop`/`active?`/`dispatch`/`message_class`. Selection + registration
via the `Configuration` module:

```ruby
Plumbing::Actor.uses :async                       # pick the default worker
Plumbing::Actor.register(:custom) { |actor| ... } # plug in your own
```

- **`inline`** — always loaded, zero-dependency default; delivers synchronously.
- **`async`** — opt-in; `Async::Queue` + `Semaphore`, `queue.async(parent:)`
  is the loop (no wrapping `while`).
- **`threaded`** — opt-in; ported from 0.x onto the `Worker` base class
  (`concurrent-ruby`). v1 passes arguments **by reference** (no marshalling);
  callers follow normal actor hygiene — don't mutate shared objects across the
  boundary.
- **`rails`** — opt-in; the Rails-safe threaded variant (wraps work in the
  ActiveSupport executor).

> **Future: `safe_threaded` / `safe_rails` (and a Ractor worker).** The 0.x
> `Transporter` (marshalling args via `globalid`) was written with a Ractor
> implementation in mind — Ractors *enforce* shareability, so arguments must be
> marshalled. A future opt-in `safe_*` worker family can reintroduce the
> Transporter (and `globalid` as a worker-only dep) for AR-safe / Ractor-safe
> argument passing, without burdening the default `threaded`/`rails` workers.

---

### 3. Services (service locator)

A **non-actor**, prefilled-at-boot registry. Reads are synchronous and
lock-free; the list is assumed immutable after startup. (A later actor-based
variant can support clients dropping on/off the network dynamically — YAGNI
for now.)

- Global default `Plumbing.services`, or construct your own instances and
  manage them independently (à la `Fabrik.db`).

Two registration methods, three lifetimes:

```ruby
# SINGLETON — always the same object back.  (alias: singleton)
Plumbing.services.register :config, AppConfig.load    # eager: object supplied now
Plumbing.services.register(:db) { Database.connect }  # lazy: built once, on first access, cached

# FACTORY — a fresh object every access.  (alias: factory)
Plumbing.services.create(:clock) { Time.now }
```

Primary names are `register` / `create` (less computer-sciencey); `singleton` /
`factory` are aliases for those who prefer the DI terms.

- `register(name, object = nil, &builder)` — eager when handed an object,
  lazy-once when handed a block. Alias: `singleton`.
- `create(name, &builder)` — builds a new instance on every lookup. Alias:
  `factory`.
- Validation: exactly one of `object` / `builder` for `register`; a block is
  required for `create`.

Access (synchronous — no `await`, because it's not an actor):

```ruby
Plumbing.services[:db]
```

---

### 4. Pipeline + Event (composable event stream)

Implemented **as actors**, so they're concurrency-safe. The old `Pipe`,
rebuilt around immutable events.

#### Events

```ruby
class SomethingHappened < Plumbing::Event   # Plumbing::Event < Literal::Data
  prop :id, String
end
```

- Events are `Literal::Data` descendants → frozen, immutable, **value
  equality on all props**, and prop-based `hash` (so Set-based debounce is
  O(1)).
- `Plumbing::Pipeline.register` records event classes for safe deserialisation:
  - `param :class, _Descendant(Plumbing::Event)`

#### Operations

- `push(event, debounce: true)` / alias `<<` — emit an event
  - `param :event, _Descendant(Plumbing::Event)`
- `notify(event_type, debounce: true, **params)` — build a *registered* event
  by type name, then emit it
  - `param :event_type, String`
  - `param :params, _Hash?, :**, default: {}.freeze`
- `observe(&observer)` — register an observer (`param :observer, Proc, :&`)
- `remove(observer)` — deregister one (`param :observer, Proc`)
- `remove_all` — deregister everything

#### Debounce / batching

`push` adds the event to an internal **ordered queue** and triggers a *single*
asynchronous `notify_observers` pass. This:

- debounces duplicates (duplicate = value-equal event) using a **`Set` as a
  dedup index**: `@queue << event if @seen.add?(event)`. `Set#add?` returns
  `nil` when the event is already present, so an equal event enqueues at most
  once. Events are `Literal::Data` (prop-based `hash`/`eql?`), so value-equality
  works correctly as Set membership.
- coalesces a burst of pushes into one async task + one notify pass, rather
  than spawning an async task per event.

The queue itself stays an ordered Array — it preserves emission order, and lets
`debounce: false` push an intentional duplicate through (the `Set` is *only* the
fast membership filter for the `debounce: true` path, not the queue itself).
Each notify pass drains the queue in order, then clears both the queue and the
Set. (A bare `Set` as the queue is tempting — it auto-dedupes and Ruby Sets keep
insertion order — but it can't express `debounce: false`, so we keep them
separate.)

#### Composition algebra

An abstract `Pipeline::Base`, with concrete subclasses. Event-type matching
is by the event's type name; `Only`/`Except` support `EventType*` wildcards,
`Filter` takes raw `Regexp` (deliberately redundant with `Only` — two
friendly forms plus one powerful form).

| Class | Role | Props |
|---|---|---|
| `Pipeline::Source` | basic origin | — |
| `Pipeline::Only` | emit only matching event-types | `source: _Descendant(Pipeline::Base)`, `filters: _Array[String], :*` |
| `Pipeline::Except` | emit all *except* matching | `source: _Descendant(Pipeline::Base)`, `filters: _Array[String], :*` |
| `Pipeline::Filter` | emit only `Regexp`-matching | `source: _Descendant(Pipeline::Base)`, `filters: _Array[Regexp], :*` |
| `Pipeline::Junction` | fan-in: merge many sources | `sources: _Array[_Descendant(Pipeline::Base)], :*` |

```ruby
errors = Pipeline::Only.new(
  source: Pipeline::Junction.new(app_events, worker_events),
  filters: ["Error*", "Critical*"],
)
errors.observe { |event| alert(event) }
```

## Open implementation details (resolve during build, not blocking)

- ~~Verify `literal`'s `Literal.check` argument order~~ — **resolved:**
  `Literal.check(value, type)` (positional), confirmed against `literal 1.9.0`.
- `threaded` worker arg-passing: direct reference vs marshalled `Transporter`
  (and whether `globalid` rides along as a `threaded`-only optional dep).
- Test helpers: a v1 equivalent of the old `Plumbing::Spec.modes` /
  `become_matchers` for exercising each worker.
- `CHANGELOG.md` + a short 0.x → 1.0 migration note.
