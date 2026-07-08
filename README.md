# Plumbing

Small, fast building blocks for concurrent Ruby: **actors**, a **service
locator**, a **composable event stream**, **observable** objects and a
**state-machine engine** — built on
[`literal`](https://github.com/joeldrapper/literal) and nothing else.

> **v1 is a breaking rewrite** (`0.5.2 → 1.0.0`). See the
> [CHANGELOG](CHANGELOG.md) for what changed.

## Philosophy

Plumbing gives you the few concurrency patterns an app actually needs without
the surface area of the `dry-*` family. The core gem's **only runtime
dependency is `literal`**. Anything heavier is opt-in — you `require` it and
add the underlying gem yourself.

## Concepts

### Actors

Asynchronous, thread-safe objects. `include Plumbing::Actor`, declare typed
async messages, and resolve results with `await`.

```ruby
class Greeting
  include Plumbing::Actor
  def initialize(name:) = @name = name

  async :say do
    param :greeting, String, default: "Hello"
    returns { |greeting:| "#{greeting} #{@name}" }  # validated params arrive as block kwargs
  end
end

g = Greeting.new(name: "Alice")
await { g.say(greeting: "Hi") }   # => "Hi Alice"
```

Async messages forward **blocks** as well as params — declare `&block` in the
`returns` signature and the caller's block arrives intact:

```ruby
class Speaker
  include Plumbing::Actor
  async :say_something do
    returns { |&block| "I am speaking #{block.call}" }
  end
end

await { Speaker.new.say_something { "in a block" } }   # => "I am speaking in a block"
```

Each actor owns a pluggable **worker**. `inline` (the default) ships with the
core; `async`, `threaded` and `rails` are opt-in:

```ruby
require "plumbing/actor/async"   # also: add `async` to your Gemfile
Plumbing::Actor.uses :async
```

Actors track who called them — `current_sender` (immediate) and
`current_senders` (the full call-chain).

Call `stop` to shut an actor down — it closes the worker's queue, so any
already-queued messages still run and then the consumer thread / async task
exits instead of blocking forever. Whoever owns the actor's lifecycle is
responsible for stopping it (see the Provider's `on_expiry:` below). The inline
worker has nothing to stop, so it's a no-op there.

### Providers

A parameterised object locator. `Provider` is itself a **Plumbing actor**, so
`register`, `provide` and `get` are async messages taking keyword arguments.
Lookups via `[]` are the synchronous convenience — `provider[path]` is exactly
`provider.get(path:).await`.

- `register` - registers an object at a path - lookups on that path return the same object each time
- `provide` - registers a factory at a path - lookups on that path return a new object each time

```ruby
# Every lookup returns the same object which is registered immediately
Plumbing.services.register path: "app/config", value: AppConfig.load
Plumbing.services["app/config"]

# The first lookup calls the block and subsequent lookups are cached
Plumbing.services.register(path: "db") { Database.connect }
Plumbing.services["db"]

# Each lookup calls the block
Plumbing.services.provide(path: "system/clock") { Time.now }
Plumbing.services["system/clock"]
```

The path can contain parameters which are then passed as keyword arguments to the provider block.  The arguments are always strings as they are extracted from the lookup query.  

```ruby
# Every lookup calls `Person.find`
Plumbing.services.provide(path: "people/:id") { |id:| Person.find(id) }
Plumbing.services["/people/123"]

# The first lookup calls `Person.find` and subsequent lookups are cached
Plumbing.services.register(path: "people/:id") { |id:| Person.find(id) }
Plumbing.services["/people/123"]
```

A cached registration can be given a **TTL** with `expires_in:` (seconds). After
that long the cached value is evicted and the next lookup re-resolves through the
block, restarting the clock — handy for singletons used in bursts that should
release their memory once cold. Eviction is scheduled on the actor's worker, so
it needs a worker that can defer: under the default `:inline` worker the TTL is a
silent no-op and the value caches forever (much like a cache store with no expiry
sweeper).

```ruby
# Re-fetched at most once every 60s; evicted in between so it can be reclaimed
Plumbing.services.register(path: "exchange/rates", expires_in: 60) { RateApi.fetch }
```

By default eviction just drops the cached value — the Provider does **not** touch
its lifecycle, since the same object may be used elsewhere. If the cached value
owns a resource that must be released on eviction (an actor's worker thread, a
connection, a file handle), pass `on_expiry:` — a **Symbol** sent to the evicted
value, or a **callable** that receives it. It only fires when a TTL actually
evicts, so `on_expiry` without `expires_in` raises `ArgumentError`.

```ruby
# Build a fresh worker actor per 5-minute window; stop the old one when it's evicted
services.register(path: "importer", expires_in: 300, on_expiry: :stop) { Importer.start }
# `:stop` sends #stop to the actor (Plumbing::Actor exposes #stop → worker.stop)

# Or run arbitrary teardown against the evicted value
services.register(path: "pool", expires_in: 60, on_expiry: ->(p) { p.disconnect }) { Pool.open }
```

Because `register` and `provide` are async, they return a message rather than
raising inline. Registration errors (an ambiguous registration, a static value
on a dynamic path) surface only when the message is awaited, so `await` if you
need to catch them:

```ruby
provider.register(path: "locate/:object", value: "object").await   # => raises ArgumentError
```

If there is a conflict between a static path and a dynamic path, the one with the most static matches wins.  

```ruby
@provider = Plumbing::Provider.new 

@provider.register(path: "users/:id") { |id:| User.find(id) }
@provider.register(path: "users/me") { Current.user }

@provider["users/me"] # => Current.user 
```

```ruby
@provider = Plumbing::Provider.new 

# path has 2 static and 2 dynamic segments
@provider.register(path: "users/:username/comments/:comment_id") { |username:, comment_id:| "user #{username} and comment #{comment_id}" }
# path has 3 static and 1 dynamic segment
@provider.register(path: "users/alice/comments/:comment_id") { |comment_id:|  "comment #{comment_id}" }

# matches alice because the path has 3 static segments
@provider["users/alice/comments/123"] # => comment 123
@provider["users/bob/comments/123"] # => user bob and comment 123
```

**Nested providers.** Mount another Provider under a wildcard tail path
(`"prefix/*"`) and lookups beneath that prefix are delegated to it — like
mounting a sub-router. A lookup of the bare prefix returns the nested provider
itself; a lookup with a tail forwards the remaining path. Only a Provider may be
mounted under a wildcard (a static value is checked on registration; a block is
checked when it resolves).

```ruby
users = Plumbing::Provider.new
users.register(path: "me") { Current.user }

app = Plumbing::Provider.new
app.register path: "users/*", value: users

app["users"]      # => the `users` provider itself
app["users/me"]   # => Current.user  (delegates "me" to the nested provider)
```

The prefix may contain `:params`. They're captured and passed to the
registration block, so it can build a provider **scoped** to them — e.g. a
nested provider that only exposes what a given user may see:

```ruby
app.register(path: "users/:user_id/messages/*") do |user_id:|
  MessagesFor.new(user: User.find(user_id))   # a Provider scoped to that user
end

app["users/42/messages/latest"]   # => user 42's latest message, via the scoped provider
```

Because this is `register`, the built provider is **cached** — one per parameter
set — and reused, so an expensive scoped provider isn't rebuilt on every lookup.
Pass `expires_in:` to bound how long each cached provider is kept, and
`on_expiry:` (as above) to tear each scoped provider down when it's evicted —
e.g. `on_expiry: :stop` to shut down the nested provider's worker. (A static
value can't bind `:params`, so a parameterised prefix must be given a block —
registering one with a value raises `ArgumentError`.)

Paths are automatically stripped of leading and trailing slashes.  

Use the global `Plumbing.services`, or build and manage your own registry instances independently.

### Pipeline + Event

A composable, concurrency-safe event stream over immutable `Literal::Data`
events.

```ruby
class SomethingHappened < Plumbing::Event
  prop :id, String
end

errors = Pipeline::Only.new(
  source: Pipeline::Junction.new(app_events, worker_events),
  filters: ["Error*", "Critical*"],
)
errors.observe { |event| alert(event) }

app_events << SomethingHappened.new(id: "123")
```

Compose with `Source`, `Only`, `Except`, `Filter` (regexp) and `Junction`
(fan-in). Pushes are debounced and batched into a single notify pass.

### Observable

Mix `Plumbing::Observable` into any object — actor or not — to give it its own
event stream. The host gains a public subscriber interface (`observe`, `remove`,
`remove_all`) and a private emit interface (`push`, `notify`), backed by a
lazily-created internal `Pipeline::Source`. Because the pipeline is the actor,
these methods need not be async — they forward fire-and-forget.

```ruby
class Thermostat
  include Plumbing::Observable

  def temperature=(celsius)
    @temperature = celsius
    push TemperatureChanged.new(celsius: celsius)   # private — only the host emits
  end
end

t = Thermostat.new
t.observe { |event| puts "now #{event.celsius}°C" }
t.temperature = 21   # => "now 21°C"
```

Observers subscribe from the outside; only the host emits. `Plumbing::Operation`
is built on this — its lifecycle events (`Started`, `Transitioned`, …) are pushed
through an `Observable` stream.

### Operation

A state-machine engine for multi-step processes. Subclass `Plumbing::Operation`,
declare typed **attributes** and a graph of **states** with the class DSL. An
Operation is itself a **Plumbing actor**, so each one advances on its own worker
and its steps never interleave with another operation's.

There are four kinds of state:

- **`action`** — runs a block on entry (it may assign attributes), then follows
  its single `.then` transition.
- **`decision`** — picks the first `go_to` whose `if:` guard matches; a bare
  `go_to` is the else branch. No match raises `NoDecision`.
- **`wait`** — pauses until a guard matches, polling every `delay` seconds up to
  a `timeout` (raising `Timeout`). Waits need a worker that can defer, so an
  operation with any wait state raises `NotSupported` up front under the default
  `:inline` worker — select `:async` or `:threaded`.
- **`result`** — terminal; entering one completes the operation.

Guards and action bodies run in the operation's own context, so they read and
write attributes directly.

```ruby
class Checkout < Plumbing::Operation
  attribute :total, Integer
  attribute :discounted, _Nilable(Integer)

  starts_with :check
  decision :check do
    go_to :apply_discount, "over £100", if: -> { total > 100 }
    go_to :done, "full price"
  end
  action(:apply_discount) { self.discounted = (total * 0.9).to_i }.then :done
  result :done
end

op = Checkout.call(total: 150)
op.completed?      # => true
op.current_state   # => :done
op.discounted      # => 135
```

Start one with `.call(**attributes)`. Inspect it with `current_state`,
`in?(:state)`, `completed?`, `failed?`, `exception` and `attributes`. If a step
raises, the operation moves to `failed?` and captures the `exception` rather
than blowing up the caller. `.test(:state, **attrs)` starts partway through the
graph, which is handy in specs.

**Waits and interactions** (async/threaded worker). A `wait_until` polls its
guard; class-level `delay` / `timeout` set the defaults (10s / 24h) and each
wait can override them. An `interaction` is an external message, valid only in a
given state (`InvalidState` otherwise), that pokes a waiting operation — e.g. to
supply the input it's blocked on — and wakes it immediately instead of at the
next poll.

```ruby
require "plumbing/actor/async"
Plumbing::Actor.uses :async

class Registration < Plumbing::Operation
  attribute :name, _Nilable(String)
  delay 0.05
  timeout 5.0

  starts_with :await_name
  wait_until(:await_name) { go_to :greet, "named", if: -> { !name.nil? } }
  action(:greet) { self.name = "Hello #{name}" }.then :done
  result :done

  interaction(:provide_name) { |value| self.name = value }.when :await_name
end

op = Registration.call            # parks in :await_name
op.provide_name("Cher")           # wakes it → completes
```

Because a wait can span a long time, an operation can be **persisted and
resumed**: observe its lifecycle events for a durable record, then rebuild it
later with `.restore(state:, wait_elapsed:, **attributes)`.

**Events.** Every checkpoint pushes a lifecycle event through the operation's
`Observable` stream — `Started`, `Transitioned`, `Waiting`, `Completed`,
`Failed` — each carrying the operation id, state, and a full attributes
snapshot (enough for an observer to upsert into a store). Pass a `pipeline:` at
construction to capture them:

```ruby
events = Plumbing::Pipeline::Source.new
events.observe { |event| persist(event) }
Checkout.call(pipeline: events, total: 150)
```

**Diagrams, both ways.** `YourOperation.to_mermaid` renders the state graph as a
mermaid `flowchart TD` — action/decision/wait/result each get their own node
shape and transitions become labelled edges. The inverse is an opt-in authoring
tool: `require "plumbing/operation/generator"`, then
`Plumbing::Operation::Generator.from_mermaid(diagram, class_name: "YourOperation")`
turns a flowchart back into an Operation skeleton (guard and action bodies
stubbed with `raise NotImplementedError`), so a diagram can be the source of
truth for the shape of a process.

## Installation

```sh
bundle add standard-procedure-plumbing
```

```ruby
require "plumbing"
```

Note: this gem is licensed under the [LGPL](/LICENCE), which may or may not
make it unsuitable for use by you or your company.

## Development

After checking out the repo, run `bin/setup` to install dependencies, then
`rake spec` to run the tests. `bin/console` gives you an interactive prompt.

To install locally, run `bundle exec rake install`. To release, update the
version in `lib/plumbing/version.rb` and run `bundle exec rake release`.

## Contributing

Bug reports and pull requests are welcome on GitHub at
<https://github.com/standard-procedure/plumbing>. This project follows a
[code of conduct](https://github.com/standard-procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).
