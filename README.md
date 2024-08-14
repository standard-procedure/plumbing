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
    # if we've already stored 2 events in the buffer then broadcast the newest event and clear the buffer
    if @events.count >= 2
      @events.clear
      self << event
    end
  end
end

@source = Plumbing::Pipe.start
@filter = EveryThirdEvent.new(source: @source)

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

## Plumbing::Chain - a chain of operations that occur in sequence

Define a sequence of operations that proceed in order, passing their output from one operation as the input to another.

You can define pre-conditions (which validate the inputs supplied) or post-conditions (which validate the output).  

### Usage:

```ruby
require "plumbing"
class BuildSequence < Plumbing::Chain 
  pre_condition :must_be_an_array do |input| 
    input.is_a? Array 
  end

  post_condition :must_have_three_elements do |output|
    # yes, this is a stupid post-condition but it shows how you can ensure your outputs are valid
    output.length == 3
  end

  perform :add_first
  perform :add_second
  perform :add_third

  private 

  def add_first input 
    input << "first"
  end

  def add_second input 
    input << "second" 
  end

  def add_third input 
    input << "third"
  end
end

BuildSequence.new.call []
# => ["first", "second", "third"]

BuildSequence.new.call 1
# => Plumbing::PreconditionError("must_be_an_array")

BuildSequence.new.call ["extra element"]
# => Plumbing::PostconditionError("must_have_three_elements")
```

## Installation

Install the gem and add to the application's Gemfile by executing:

```sh
bundle add standard-procedure-plumbing
```

Then:

```ruby
require 'plumbing'
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/standard_procedure/plumbing. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Plumbing project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).
