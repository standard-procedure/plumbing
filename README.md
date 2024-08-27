# Plumbing

## Plumbing::Pipeline - transform data through a pipeline

Define a sequence of operations that proceed in order, passing their output from one operation as the input to another.  [Unix pipes](https://en.wikipedia.org/wiki/Pipeline_(Unix)) in Ruby.  

Use `perform` to define a step that takes some input and returns a different output.  
  Specify `using` to re-use an existing `Plumbing::Pipeline` as a step within this pipeline.  
Use `execute` to define a step that takes some input, performs an action but passes the input, unchanged, to the next step.  

If you have [dry-validation](https://dry-rb.org/gems/dry-validation/1.10/) installed, you can validate your input using a `Dry::Validation::Contract`.  Alternatively, you can define a `pre_condition` to test that the inputs are valid.  

You can also verify that the output generated is as expected by defining a `post_condition`.  

### Usage:

[Building an array using multiple steps with a pre-condition and post-condition](/spec/examples/pipeline_spec.rb)

```ruby
require "plumbing"
class BuildArray < Plumbing::Pipeline
  perform :add_first
  perform :add_second
  perform :add_third

  pre_condition :must_be_an_array do |input|
    input.is_a? Array
  end

  post_condition :must_have_three_elements do |output|
    output.length == 3
  end

  private

  def add_first(input) = input << "first"

  def add_second(input) = input << "second"

  def add_third(input) = input << "third"
end

BuildArray.new.call []
# => ["first", "second", "third"]

BuildArray.new.call 1
# => Plumbing::PreconditionError("must_be_an_array")

BuildArray.new.call ["extra element"]
# => Plumbing::PostconditionError("must_have_three_elements")
```

[Validating input parameters with a contract](/spec/examples/pipeline_spec.rb)
```ruby
require "plumbing"
require "dry/validation"

class SayHello < Plumbing::Pipeline
  validate_with "SayHello::Input"
  perform :say_hello

  private

  def say_hello input
    "Hello #{input[:name]} - I will now send a load of annoying marketing messages to #{input[:email]}"
  end

  class Input < Dry::Validation::Contract
    params do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end
    rule :email do
      key.failure("must be a valid email") unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match? value
    end
  end
end

SayHello.new.call(name: "Alice", email: "alice@example.com")
# => Hello Alice - I will now send a load of annoying marketing messages to alice@example.com 

SayHello.new.call(some: "other data")
# => Plumbing::PreConditionError
```

[Building a pipeline through composition](/spec/examples/pipeline_spec.rb)

```ruby
require "plumbing"
class ExternalStep < Plumbing::Pipeline
  perform :add_item_to_array

  private

  def add_item_to_array(input) = input << "external"
end

class BuildSequenceWithExternalStep < Plumbing::Pipeline
  perform :add_first
  perform :add_second, using: "ExternalStep"
  perform :add_third

  private

  def add_first(input) = input << "first"

  def add_third(input) = input << "third"
end

BuildSequenceWithExternalStep.new.call([])
# => ["first", "external", "third"]
```

## Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply just registering for notifications from a single observable, we can build sequences of pipes.  These sequences can filter notifications and route them to different listeners, or merge multiple sources into a single stream of notifications.  

By default, pipes work synchronously, using a [Plumbing::EventDispatcher](lib/plumbing/event_dispatcher.rb) but if asynchronous events are needed, that can be swapped out for a [fiber-based implementation](lib/plumbing/event_dispatcher/fiber.rb).  (Threads and/or Ractor-based implementations will probably be coming soon).

### Usage

[A simple observer](/spec/examples/pipe_spec.rb):
```ruby
require "plumbing"

@source = Plumbing::Pipe.start
@observer = @source.add_observer do |event|
  puts event.type
end

@source.notify "something_happened", message: "But what was it?"
# => "something_happened"
```

[Simple filtering](/spec/examples/pipe_spec.rb):
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

[Custom filtering](/spec/examples/pipe_spec.rb):
```ruby
require "plumbing"
class EveryThirdEvent < Plumbing::CustomFilter
  def initialize source:
    super source: source
    @events = []
  end

  def received event
    # store this event into our buffer
    @events << event
    # if this is the third event we've received then clear the buffer and broadcast the latest event
    if @events.count >= 3
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

[Joining multiple sources](/spec/examples/pipe_spec.rb):
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

[Dispatching events asynchronously (using Fibers)](/spec/examples/pipe_spec.rb):
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

[Casting objects as duck-types](/spec/examples/rubber_duck_spec.rb):
```ruby
require "plumbing"

Person = Plumbing::RubberDuck.define :first_name, :last_name, :email 
LikesFood = Plumbing::RubberDuck.define :favourite_food 

PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
CarData = Struct.new(:make, :model, :colour)

@porsche_911 = CarData.new "Porsche", "911", "black"
@person = @porsche_911.as Person
# => Raises a TypeError as CarData does not respond_to #first_name, #last_name, #email

@alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"
@person = @alice.as Person
@person.first_name
# => "Alice"
@person.email 
# => "alice@example.com"
@person.favourite_food
# => NoMethodError - #favourite_food is not part of the Person rubber duck (even though it is part of the underlying PersonData struct)

# Cast our Person into a LikesFood rubber duck
@hungry = @person.as LikesFood 
@hungry.favourite_food 
# => "Ice cream"
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
