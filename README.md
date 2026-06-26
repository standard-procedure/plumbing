# Plumbing

Small, fast building blocks for concurrent Ruby: **actors**, a **service
locator** and a **composable event stream** — built on
[`literal`](https://github.com/joeldrapper/literal) and nothing else.

> **v1 is a breaking rewrite** (`0.5.2 → 1.0.0`), in progress on the `v1`
> branch. See [DESIGN.md](DESIGN.md) for the full specification and
> [PLAN.md](PLAN.md) for the build order.

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

Each actor owns a pluggable **worker**. `inline` (the default) ships with the
core; `async`, `threaded` and `rails` are opt-in:

```ruby
require "plumbing/actor/async"   # also: add `async` to your Gemfile
Plumbing::Actor.uses :async
```

Actors track who called them — `current_sender` (immediate) and
`current_senders` (the full call-chain).

### Services

A lock-free service locator, prefilled at startup.

```ruby
Plumbing.services.register :config, AppConfig.load    # eager singleton  (alias: singleton)
Plumbing.services.register(:db) { Database.connect }  # lazy singleton, built once
Plumbing.services.create(:clock) { Time.now }         # new instance every access (alias: factory)

Plumbing.services[:db]
```

Use the global `Plumbing.services`, or build and manage your own registry
instances independently.

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
