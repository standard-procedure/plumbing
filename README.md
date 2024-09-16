# Plumbing

Actors, Observers and Data Pipelines.

## Configuration

The most important configuration setting is the `mode`, which governs how background tasks are handled.

By default it is `:inline`, so every command or query is handled synchronously.  This is the ruby behaviour you know and love (although see the section on `await` below).

`:async` mode handles tasks using fibers (via the [Async gem](https://socketry.github.io/async/index.html)).  Your code should include the "async" gem in its bundle, as Plumbing does not load it by default.

`:threaded` mode handles tasks using a thread pool via [Concurrent Ruby](https://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/Promises.html)).  Your code should include the "concurrent-ruby" gem in its bundle, as Plumbing does not load it by default.

However, `:threaded` mode is not safe for Ruby on Rails applications.  In this case, use `:threaded_rails` mode, which is identical to `:threaded`, except it wraps the tasks in the Rails executor.  This ensures your actors do not interfere with the Rails framework.  Note that the Concurrent Ruby's default `:io` scheduler will create extra threads at times of high demand, which may put pressure on the ActiveRecord database connection pool.  A future version of plumbing will allow the thread pool to be adjusted with a maximum number of threads, preventing contention with the connection pool.

The `timeout` setting is used when performing queries - it defaults to 30s.

```ruby
  require "plumbing"
  puts Plumbing.config.mode
  # => :inline

  Plumbing.configure mode: :async, timeout: 10

  puts Plumbing.config.mode
  # => :async
```

If you are running a test suite, you can temporarily update the configuration by passing a block.

```ruby
  require "plumbing"
  puts Plumbing.config.mode
  # => :inline

  Plumbing.configure mode: :async do
    puts Plumbing.config.mode
    # => :async
    first_test
    second_test
  end

  puts Plumbing.config.mode
  # => :inline
```

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

## Plumbing::Actor - safe asynchronous objects

An [actor](https://en.wikipedia.org/wiki/Actor_model) defines the messages an object can receive, similar to a regular object.
However, in traditional object-orientated programming, a thread of execution moves from one object to another.  If there are multiple threads, then each object may be accessed concurrently, leading to race conditions or data-integrity problems - and very hard to track bugs.

Actors are different.  Conceptually, each actor has it's own thread of execution, isolated from every other actor in the system.  When one actor sends a message to another actor, the receiver does not execute its method in the caller's thread.  Instead, it places the message on a queue and waits until its own thread is free to process the work.  If the caller would like to access the return value from the method, then it must wait until the receiver has finished processing.

This means each actor is only ever accessed by a single thread and the vast majority of concurrency issues are eliminated.

[Plumbing::Actor](/lib/plumbing/actor.rb) allows you to define the `async` public interface to your objects.  Calling `.start` builds a proxy to the actual instance of your object and ensures that any messages sent are handled in a manner appropriate to the current mode - immediately for inline mode, using fibers for async mode and using threads for threaded and threaded_rails mode.

When sending messages to an actor, this just works.

However, as the caller, you do not have direct access to the return values of the messages that you send.  Instead, you must call `#value` - or alternatively, wrap your call in `await { ... }`.  The block form of `await` is added in to ruby's `Kernel` so it is available everywhere.  It is also safe to use with non-actors (in which case it just returns the original value from the block).

```ruby
@actor = MyActor.start name: "Alice"

@actor.name.value
# => "Alice"

await { @actor.name }
# => "Alice"

await { "Bob" }
# => "Bob"
```

This then makes the caller's thread block until the receiver's thread has finished its work and returned a value.  Or if the receiver raises an exception, that exception is then re-raised in the calling thread.

The actor model does not eliminate every possible concurrency issue.  If you use `value` or `await`, it is possible to deadlock yourself.

Actor A, running in Thread 1, sends a message to Actor B and then awaits the result, meaning Thread 1 is blocked.  Actor B, running in Thread 2, starts to work, but needs to ask Actor A a question.  So it sends a message to Actor A and awaits the result.  Thread 2 is now blocked, waiting for Actor A to respond.  But Actor A, running in Thread 1, is blocked, waiting for Actor B to respond.

This potential deadlock only occurs if you use `value` or `await` and have actors that call back in to each other.  If your objects are strictly layered, or you never use `value` or `await` (perhaps, instead using a Pipe to observe events), then this particular deadlock should not occur.  However, just in case, every call to `value` has a timeout defaulting to 30s.

### Inline actors

Even though inline mode is not asynchronous, you must still use `value` or `await` to access the results from another actor.  However, as deadlocks are impossible in a single thread, there is no timeout.

### Async actors

Using async mode is probably the easiest way to add concurrency to your application.  It uses fibers to allow for "concurrency but not parallelism" - that is execution will happen in the background but your objects or data will never be accessed by two things at the exact same time.

### Threaded actors

Using threaded (or threaded_rails) mode gives you concurrency and parallelism.  If all your public objects are actors and you are careful about callbacks then the actor model will keep your code safe.  But there are a couple of extra things to consider.

Firstly, when you pass parameters or return results between threads, those objects are "transported" across the boundaries.
Most objects are cloned. Hashes, keyword arguments and arrays have their contents recursively transported.  And any object that uses `GlobalID::Identification` (for example, ActiveRecord models) are marshalled into a GlobalID, then unmarshalled back in to their original object.  This is to prevent the same object from being amended in both the caller and receiver's threads.

Secondly, when you pass a block (or Proc parameter) to another actor, the block/proc will be executed in the receiver's thread.  This means you must not access any variables that would normally be in scope for your block (whether local variables or instance variables of other objects - see note below)  This is because you will be accessing them from a different thread to where they were defined, leading to potential race conditions.  And, if you access any actors, you must not use `value` or `await` or you risk a deadlock.  If you are within an actor and need to pass a block or proc parameter, you should use the `safely` method to ensure that your block is run within the context of the calling actor, not the receiving actor.

For example, when defining a custom filter,  the filter adds itself as an observer to its source.  The source triggers the `received` method on the filter, which will run in the context of the source.  So the custom filter uses `safely` to move back into its own context and access its instance variables.

```ruby
class EveryThirdEvent < Plumbing::CustomFilter
  def initialize source:
    super
    @events = []
  end

  def received event
    safely do
      @events << event
      if @events.count >= 3
        @events.clear
        self << event
      end
    end
  end
end
```

(Note: we break that rule in the specs for Pipe objects - we use a block observer that sets the value on a local variable.  That's because it is a controlled situation where we know there are only two threads involved and we are explicitly waiting for the second thread to complete.  For almost every app that uses actors, there will be multiple threads and it will be impossible to predict the access patterns).

### Constructing actors

Instead of constructing your object with `.new`, use `.start`.  This builds a proxy object that wraps the target instance and dispatches messages through a safe mechanism.  Only messages that have been defined as part of the actor are available in this proxy - so you don't have to worry about callers bypassing the actor's internal context.

### Referencing actors

If you're within a method inside your actor and you want to pass a reference to yourself, instead of using `self`, you should use `proxy` (which is also aliased as `as_actor` or `async`).

Also be aware that if you use actors in one place, you need to use them everywhere - especially if you're using threads.  This is because as the actor sends messages to its collaborators, those calls will be made from within the actor's internal context.  If the collaborators are also actors, the subsequent messages will be handled correctly, if not, data consistency bugs could occur.  This does not mean that every class needs to be an actor, just your "public API" classes which may be accessed from multiple actors or other threads.

### Usage

[Defining an actor](/spec/examples/actor_spec.rb)

```ruby
  require "plumbing"

  class Employee
    include Plumbing::Actor
    async :name, :job_title, :greet_slowly, :promote
    attr_reader :name, :job_title

    def initialize(name)
      @name = name
      @job_title = "Sales assistant"
    end

    private

    def promote
      sleep 0.5
      @job_title = "Sales manager"
    end

    def greet_slowly
      sleep 0.2
      "H E L L O"
    end
  end

  @person = Employee.start "Alice"

  await { @person.name }
  # =>  "Alice"
  await { @person.job_title }
  # => "Sales assistant"

  # by using `await`, we will block until `greet_slowly` has returned a value
  await { @person.greet_slowly }
  # =>  "H E L L O"

  # this time, we're not awaiting the result, so this will run in the background (unless we're using inline mode)
  @person.greet_slowly

  # this will run in the background
  @person.promote
  # this will block - it will not return until the previous calls, #greet_slowly, #promote, and this call to #job_title have completed
  await { @person.job_title }
  # => "Sales manager"
```

## Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply just registering for notifications from a single observable, we can build sequences of pipes.  These sequences can filter notifications and route them to different listeners, or merge multiple sources into a single stream of notifications.

Pipes are implemented as actors, meaning that event notifications can be dispatched asynchronously.  The observer's callback will be triggered from within the pipe's internal context so you should immediately trigger a command on another actor to maintain safety.

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
      # #received is called in the context of the `source` actor
      # in order to safely access the `EveryThirdEvent` instance variables
      # we need to move into the context of our own actor
      safely do
        # store this event into our buffer
        @events << event
        # if this is the third event we've received then clear the buffer and broadcast the latest event
        if @events.count >= 3
          @events.clear
          self << event
        end
      end
    end
  end

  @source = Plumbing::Pipe.start
  @filter = EveryThirdEvent.start(source: @source)
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
## Plumbing::RubberDuck - duck types and type-casts

Define an [interface or protocol](https://en.wikipedia.org/wiki/Interface_(object-oriented_programming)) specifying which messages you expect to be able to send.

Then cast an object into that type.  This first tests that the object can respond to those messages and then builds a proxy that responds to those messages (and no others).  However, if you take one of these proxies, you can safely re-cast it as another type (as long as the original target object responds to the correct messages).

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

You can also use the same `@object.as type` to type-check instances against modules or classes.  This creates a RubberDuck proxy based on the module or class you're casting into.  So the cast will pass if the object responds to the correct messages, even if a strict `.is_a?` test would fail.

```ruby
  require "plumbing"

  module Person
    def first_name = @first_name

    def last_name = @last_name

    def email = @email
  end

  module LikesFood
    def favourite_food = @favourite_food
  end

  PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
  CarData = Struct.new(:make, :model, :colour)

  @porsche_911 = CarData.new "Porsche", "911", "black"
  expect { @porsche_911.as Person }.to raise_error(TypeError)

  @alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

  @alics.is_a? Person
  # => false - PersonData does not `include Person`
  @person = @alice.as Person
  # This cast is OK because PersonData responds to :first_name, :last_name and :email
  expect(@person.first_name).to eq "Alice"
  expect(@person.email).to eq "alice@example.com"
  expect { @person.favourite_food }.to raise_error(NoMethodError)

  @hungry = @person.as LikesFood
  expect(@hungry.favourite_food).to eq "Ice cream"
```

## Installation

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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/standard_procedure/plumbing. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Plumbing project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/standard_procedure/plumbing/blob/main/CODE_OF_CONDUCT.md).
