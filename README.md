# Plumbing

Actors, Observers and Data Pipelines.

## Usage

Start off by [configuring Plumbing](/docs/config.md) and selecting your `mode`.

## Pipelines

[Data transformations](/docs/pipelines.md) similar to unix pipes.

## Actors

[Asynchronous, thread-safe, objects](/docs/actors.md).

## Pipes

[Composable observers](/docs/pipes.md).

## Rubber ducks

[Type-safety the ruby way](/docs/rubber_ducks.md).

## Installation

Note: this gem is licensed under the [LGPL](/LICENCE).  This may or may not make it unsuitable for use by you or your company.

Install the gem and add to the application's Gemfile by executing:

```sh
bundle add standard-procedure-plumbing
```

Then:

```ruby
require 'plumbing'

# Set the mode for your Actors and Pipes
Plumbing.config mode: :async
```

## Development

### To Do

- [ ] Add a buffered and a debouncing filter for pipes
- [ ] Pass the mode as a block parameter in `Plumbing::Spec.modes`
- [ ] Separate modes into their own object (to allow registration of new modes)
- [ ] Move Plumbing::Actor::Transporter to Plumbing::Transporter ?? (planning to use it outside of Plumbing so would make sense not to imply it is tied to Actors)
- [X] Ensure transporters deal with GlobalID models not being found / errors when unpacking

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/standard_procedure/plumbing>. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Plumbing project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).
