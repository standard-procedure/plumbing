## [1.0.0] - unreleased — v1 rewrite

A ground-up rewrite. Plumbing is now a small, [`literal`](https://github.com/joeldrapper/literal)-based
toolkit with three concepts: pluggable-worker **Actors**, a **Services**
locator, and a composable **Event / Pipeline** stream. See `DESIGN.md`.

**The only runtime dependency is `literal`.** `globalid` is dropped. The
heavier worker dependencies (`async`, `rails`) are no longer in the core — the
opt-in workers `require` their own and you add the gem to your app.

### Breaking changes

**RubberDuck removed — use `Object#as` with a literal interface:**

```ruby
obj.as(Plumbing::Callable)            # before — returned a narrowing proxy
obj.as(Literal::Types._Callable)      # after  — validates and returns obj itself
obj.as(Plumbing::Observable)          # Observable = _Interface(:observe, :remove, :remove_all)
```

**`Plumbing::Pipeline` is now the event stream (was `Plumbing::Pipe`).** The old
sequential-operations `Pipeline` is removed; the old `Pipe` message bus is
reborn as `Pipeline`, rebuilt around immutable `Plumbing::Event` values:

```ruby
# before (0.x Pipe) — observers got (event_name, data)
pipe.add_observer { |event_name, data| ... }
pipe.notify "something_happened", foo: 1

# after (1.0 Pipeline) — events are Plumbing::Event value objects
class SomethingHappened < Plumbing::Event
  prop :foo, Integer
end
source = Plumbing::Pipeline::Source.new
source.observe { |event| ... }
source << SomethingHappened.new(foo: 1)

# or via the registry, by type name:
Plumbing::Pipeline.register(SomethingHappened)
source.notify(event_type: "SomethingHappened", params: {foo: 1})
```

Compose with `Only` / `Except` (string names, trailing `*` wildcard), `Filter`
(Regexp) and `Junction` (fan-in). Duplicate events are debounced.

**Actors rebuilt (composition, not proxies):**

```ruby
# before — Counter.start returned a proxy; methods were plain defs
class Counter
  include Plumbing::Actor
  async :increment
  def increment(by = 1) = @count += by
end
counter = Counter.start
counter.increment

# after — the async DSL carries typed params; resolve with await
class Counter
  include Plumbing::Actor
  async :increment do
    param :by, Integer, default: 1
    returns { |by:| @count += by }
  end
end
counter = Counter.new
await { counter.increment(by: 2) }
```

- Worker selection moved from `Plumbing.config(mode: :async)` to
  `Plumbing::Actor.uses :async` (after `require "plumbing/actor/async"`).
- Workers: `inline` (default, zero-dependency), and opt-in `async`, `threaded`
  (now core Ruby — no `concurrent-ruby`) and `rails`. Each delivers an actor's
  messages **one at a time, in arrival order**.
- Actors now track who called them: `current_sender` / `current_senders`.

**New: Services locator** — `register`/`provide` (aliases `singleton`/`factory`):

```ruby
Plumbing.services.register(:config, AppConfig.load)   # eager singleton
Plumbing.services.register(:db) { Database.connect }  # lazy singleton
Plumbing.services.create(:clock) { Time.now }         # fresh every access
Plumbing.services[:db]
```

## [0.5.2] - 2024-10-08

 - Ensure preconditions are called in order

## [0.5.1] - 2024-10-08

 - Added exception handling for Pipeline preconditions

## [0.5.0] - 2024-09-20

 - Feature complete?

## [0.4.5] - 2024-09-20

 - Changed Plumbing::Pipeline into a module

## [0.4.5] - 2024-09-20

 - `become` matchers available to other gems
 - `wait_for`

## [0.4.4] - 2024-09-18

 - Various bugfixes around the threading implementation

## [0.4.1] - 2024-09-16

 - Added `safely` to allow actors to run code within their own context

## [0.4.0] - 2024-09-15

 - Added #as_actor to allow actors to pass references to themselves

## [0.3.3] - 2024-09-14

 - Added :threaded and :rails modes
 - RubberDuck now works with Module and Class

## [0.3.2] - 2024-09-13

 - URG - somehow I'd managed to exclude the lib folder from the gem contents

## [0.3.1] - 2024-09-03

 - Added `ignore_result` for queries on Plumbing::Valves

## [0.3.0] - 2024-08-28

 - Added Plumbing::Valve
 - Reimplemented Plumbing::Pipe to use Plumbing::Valve

## [0.2.2] - 2024-08-25

 - Added Plumbing::RubberDuck

## [0.2.1] - 2024-08-25

 - Split the Pipe implementation between the Pipe and EventDispatcher
 - Use different EventDispatchers to handle fibers or inline pipes
 - Renamed Chain to Pipeline

## [0.2.0] - 2024-08-14

 - Added optional Dry::Validation support
 - Use Async for fiber-based pipes

## [0.1.2] - 2024-08-14

 - Removed dependencies
 - Removed Ractor-based concurrent pipe (as I don't trust it yet)

## [0.1.1] - 2024-08-14

- Tidied up the code
- Added Plumbing::Chain

## [0.1.0] - 2024-04-13

- Initial release

## [Unreleased]
