# Plumbing

## Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply registering for notifications from the observable, we observe a stream of notifications, which could be produced by multiple observables, all being sent through the same pipe.  We can then chain observers together, composing a "pipeline" of operations from a single source of events.

### Usage

A simple observer:
```ruby
require "plumbing"

@source = Plumbing::Pipe.start

@observer = @source.add_observer do |event|
  puts event.type
end

@source.notify "something_happened", message: "But what was it?"
# => "something_happened"
```

Simple filtering:
```ruby
require "plumbing"

@source = Plumbing::Pipe.start

@filter = Plumbing::Filter.start source: @source, accepts: %w[important urgent]

@observer = @filter.add_observer do |event|
  puts event.type
end

@source.notify "important", message: "ALERT! ALERT!"
# => "important"

@source.notify "unimportant", message: "Nothing to see here"
# => <no output>
```

Custom filtering:
```ruby
require "plumbing"

class EveryThirdEvent < Plumbing::CustomFilter
  def initialize source:
    super source: source
    @events = []
  end

  def received event
    @events << event
    if @events.count >= 2
      @events.clear
      self << event
    end
  end
end

@source = Plumbing::Pipe.start

@filter = EveryThirdEvent.new(source :@source)

@observer = @filter.add_observer do |event|
  puts event.type
end

1.upto 10 do |i|
  @source.notify i.to_s
end
# => "3"
# => "6"
# => "9"
```

Joining multiple sources
```ruby
require "plumbing"

@first_source = Plumbing::Pipe.start
@second_source = Plumbing::Pipe.start

@join = Plumbing::Junction.start @first_source, @second_source

@observer = @join.add_observer do |event|
  puts event.type
end

@first_source.notify "one"
# => "one"
@second_source.notify "two"
# => "two"
```

## Plumbing::Chain - a chain of method calls

### Usage:

A simple chain of events
```ruby
require "plumbing"

class ContrivedExample < Plumbing::Chain
  step :validate_is_a_string
  step :validate_does_not_say_boom
  step :downcase

  private

  def validate_is_a_string input
    raise "Not a string" unless input.is_a? String
    input
  end

  def validate_does_not_say_boom input
    raise "This says BOOM which is not allowed" if input == "BOOM"
    input
  end

  def downcase input
    input.downcase
  end
end

ContrivedExample.new.call("HELLO").then(result) do
  puts result
end
# => result

ContrivedExample.new.call("BOOM").then(result) do
  puts result
end.fail(error) do
  puts error.class
end
# => RuntimeError

```

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add standard-procedure-plumbing

## Usage

Create a pipe, chain pipes together, add observers and push events

    require 'plumbing'

    @pipe = Plumbing::Pipe.start
    @filter = Plumbing::Filter.start source: @pipe, accepts: %w[important urgent]
    @observer = @filter.add_observer do |event|
      puts event.type
    end

    @pipe << Event.new(type: "unimportant", data: { some: "data"})
    # => no output
    @pipe << Event.new(type: "important", data: { some: "data"})
    # => "important"

    @filter.remove_observer @observer

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/standard_procedure/plumbing. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Plumbing project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).
