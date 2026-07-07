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
