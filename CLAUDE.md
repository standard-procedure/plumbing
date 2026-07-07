# Plumbing

Small, fast building blocks for concurrent Ruby: **actors**, a **provider**
(service locator), a **composable event pipeline**, and **operations**
(state-machine engine). Built on [`literal`](https://github.com/joeldrapper/literal)
and nothing else.

## The one hard rule

**The core gem's only runtime dependency is `literal`.** Anything heavier
(`async`, `concurrent-ruby`, Rails) is opt-in — the user `require`s it and adds
the gem themselves. Never add a runtime dependency to the gemspec to make
something convenient. If a feature needs a heavier gem, it goes behind an
explicit `require "plumbing/..."` and its own worker/adapter.

## Layout

- `lib/plumbing/actor*` — asynchronous, thread-safe objects. `include
  Plumbing::Actor`, declare `async` messages, resolve with `await`. Pluggable
  workers: `inline` (default, in core), `async`, `threaded`, `rails` (opt-in).
- `lib/plumbing/provider*` — parameterised object locator. **Itself an actor**:
  `register` / `provide` / `get` are async messages taking keyword args; `[]` is
  the sync convenience (`get(path:).await`). `Router` handles static/dynamic
  path matching (most-static wins).
- `lib/plumbing/pipeline*`, `event.rb` — composable, concurrency-safe event
  stream over immutable `Literal::Data` events (`Source`, `Only`, `Except`,
  `Filter`, `Junction`).
- `lib/plumbing/operation*` — actor-based state-machine engine (DSL → states,
  waits, interactions, restore, `to_mermaid`).

## Conventions

- **Ruby >= 3.2.0.**
- **TDD.** Tests are RSpec under `spec/`, mirroring `lib/`. Write the failing
  test first.
- **Formatting: `standard`.** Run `bundle exec standardrb --fix` before every
  commit. The default rake task is `spec standard` — both must be green.
- Actor messages take **keyword arguments** and can forward a **block**
  (declare `&block` in the `returns` signature).
- Prefer `Literal::Data` / `Literal::Struct` for value objects; lean on
  `Literal::Types` for prop typing.

## Commands

- `bin/setup` — install dependencies
- `rake spec` — run the test suite
- `rake standard` / `bundle exec standardrb --fix` — lint / autofix
- `rake` — default: spec + standard
- `bin/console` — interactive prompt

## Release

Update `lib/plumbing/version.rb`, then `bundle exec rake release`.

## Licence

LGPL — note this in anything that might affect suitability for a consumer.
