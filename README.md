# Plumbing

## Plumbing::Pipeline - transform data through a pipeline

Define a sequence of operations that proceed in order, passing their output from one operation as the input to another.  [Unix pipes](https://en.wikipedia.org/wiki/Pipeline_(Unix)) in Ruby.  

Use `perform` to define a step that takes some input and returns a different output.  
  Specify `using` to re-use an existing `Plumbing::Pipeline` as a step within this pipeline.  
Use `execute` to define a step that takes some input, performs an action but passes the input, unchanged, to the next step.  

If you have [dry-validation](https://dry-rb.org/gems/dry-validation/1.10/) installed, you can validate your input using a `Dry::Validation::Contract`.  

If you don't want to use dry-validation, you can instead define a `pre_condition` (although there's nothing to stop you defining a contract as well as pre_conditions - with the contract being verified first).  

You can also verify that the output generated is as expected by defining a `post_condition`.  

### Usage:

```ruby
require "plumbing"
class BuildSequence < Plumbing::Pipeline 
  pre_condition :must_be_an_array do |input| 
    # you could replace this with a `validate` definition (using a Dry::Validation::Contract) if you prefer
    input.is_a? Array 
  end

  post_condition :must_have_three_elements do |output|
    # this is a stupid post-condition but 🤷🏾‍♂️, this is just an example
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


## Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply registering for notifications from the observable, we observe a stream of notifications, which could be produced by multiple observables, all being sent through the same pipe.  We can then chain observers and observables together, filtering and routing events to different places as required.  

By default, pipes work synchronously, using a [Plumbing::EventDispatcher](lib/plumbing/event_dispatcher.rb) but if asynchronous events are needed, that can be swapped out for a [fiber-based implementation](lib/plumbing/event_dispatcher/fiber.rb).  (Threads and/or Ractor-based implementations will probably be coming soon).

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

@filter = Plumbing::Filter.start source: @source do |event|
  %w[important urgent].include? event.type 
end

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

@junction = Plumbing::Junction.start @first_source, @second_source

@observer = @junction.add_observer do |event|
  puts event.type
end

@first_source.notify "one"
# => "one"
@second_source.notify "two"
# => "two"
```

Dispatching events asynchronously (using Fibers)
```ruby
require "plumbing"
require "plumbing/event_dispatcher/fiber"
require "async"

# `limit` controls how many fibers can dispatch events concurrently - the default is 4
@first_source = Plumbing::Pipe.start dispatcher: Plumbing::EventDispatcher::Fiber.new limit: 8
@second_source = Plumbing::Pipe.start dispatcher: Plumbing::EventDispatcher::Fiber.new limit: 2

@junction = Plumbing::Junction.start @first_source, @second_source, dispatcher: Plumbing::EventDispatcher::Fiber.new

@filter = Plumbing::Filter.start source: @junction, dispatcher: Plumbing::EventDispatcher::Fiber.new do |event|
  %w[one-one two-two].include? event.type 
end

Sync do 
  @first_source.notify "one-one"
  @first_source.notify "one-two"
  @second_source.notify "two-one"
  @second_source.notify "two-two"
end
```


## Plumbing::RubberDuck - duck types and type-casts

Define an [interface or protocol](https://en.wikipedia.org/wiki/Interface_(object-oriented_programming)) specifying which messages you expect to be able to send.  Then cast an object into that type, which first tests that the object can respond to those messages and then builds a proxy that responds to just those messages and no others (so no-one can abuse the specific type-casting you have specified).  However, if you take one of these proxies, you can safely re-cast it as another type (as long as the original target object is castable).


### Usage 

Define your interface (Person in this example), then cast your objects (instances of PersonData and CarData).  

```ruby
require "plumbing"

Person = Plumbing::RubberDuck.define :first_name, :last_name, :email 

PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
CarData = Struct.new(:make, :model, :colour)

@porsche_911 = CarData.new "Porsche", "911", "black"
@person = @porsche_911.as Person
# => Raises a TypeError 

@alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"
@person = @alice.as Person
@person.first_name
# => "Alice"
@person.email 
# => "alice@example.com"
@person.favourite_food
# => NoMethodError - even though :favourite_food is a field in PersonData, it is not included in the definition of Person so cannot be accessed through the RubberDuck type
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
