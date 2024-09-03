# Plumbing

## Configuration 

The most important configuration setting is the `mode`, which governs how messages are handled by Valves.   

By default it is `:inline`, so every command or query is handled synchronously.  

If it is set to `:async`, commands and queries will be handled using fibers (via the [Async gem](https://socketry.github.io/async/index.html)).

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

## Plumbing::Valve - safe asynchronous objects

An [actor](https://en.wikipedia.org/wiki/Actor_model) defines the messages an object can receive, similar to a regular object.  However, a normal object if accessed concurrently can have data consistency issues and race conditions leading to hard-to-reproduce bugs.  Actors, however, ensure that, no matter which thread (or fiber) is sending the message, the internal processing of the message (the method definition) is handled sequentially.  This means the internal state of an object is never accessed concurrently, eliminating those issues.  

[Plumbing::Valve](/lib/plumbing/valve.rb) ensures that all messages received are channelled into a concurrency-safe queue. This allows you to take an existing class and ensures that messages received via its public API are made concurrency-safe.  

Include the Plumbing::Valve module into your class, define the messages the objects can respond to and set the `Plumbing` configuration to set the desired concurrency model.  Messages themselves are split into two categories: commands and queries.  

- Commands have no return value so when the message is sent, the caller does not block, the task is called asynchronously and the caller continues immediately
- Queries return a value so the caller blocks until the actor has returned a value
- However, if you call a query and pass `ignore_result: true` then the query will not block, although you will not be able to access the return value - this is for commands that do something and then return a result based on that work (which you may or may not be interested in - see Plumbing::Pipe#add_observer)
- None of the above applies if the `Plumbing mode` is set to `:inline` (which is the default) - in this case, the actor behaves like normal ruby code

Instead of constructing your object with `.new`, use `.start`.  This builds a proxy object that wraps the target instance and dispatches messages through a safe mechanism.  Only messages that have been defined as part of the valve are available in this proxy - so you don't have to worry about callers bypassing the valve's internal context.  

Even when using actors, there is one condition where concurrency may cause issues.  If object A makes a query to object B which in turn makes a query back to object A, you will hit a deadlock.  This is because A is waiting on the response from B but B is now querying, and waiting for, A.  This does not apply to commands because they do not wait for a response.  However, when writing queries, be careful who you interact with - the configuration allows you to set a timeout (defaulting to 30s) in case this happens.  

Also be aware that if you use valves in one place, you need to use them everywhere - especially if you're using threads or ractors (coming soon).  This is because as the valve sends messages to its collaborators, those calls will be made from within the valve's internal context.  If the collaborators are also valves, the subsequent messages will be handled correctly, if not, data consistency bugs could occur.  

### Usage 

[Defining an actor](/spec/examples/valve_spec.rb)

```ruby
  require "plumbing"
  
  class Employee
    attr_reader :name, :job_title

    include Plumbing::Valve
    query :name, :job_title, :greet_slowly
    command :promote

    def initialize(name)
      @name = name
      @job_title = "Sales assistant"
    end

    def promote
      sleep 0.5
      @job_title = "Sales manager"
    end

    def greet_slowly 
      sleep 0.2
      "H E L L O"
    end
  end
```

[Acting inline](/spec/examples/valve_spec.rb) with no concurrency

```ruby
  require "plumbing"
    
  @person = Employee.start "Alice"

  puts @person.name
  # => "Alice"
  puts @person.job_title
  # => "Sales assistant"

  @person.promote
  # this will block for 0.5 seconds
  puts @person.job_title
  # => "Sales manager"

  @person.greet_slowly 
  # this will block for 0.2 seconds before returning "H E L L O"

  @person.greet_slowly(ignore_result: true)
  # this will block for 0.2 seconds (as the mode is :inline) before returning nil
```

[Using fibers](/spec/examples/valve_spec.rb) with concurrency but no parallelism

```ruby
  require "plumbing"
  require "async"

  Plumbing.configure mode: :async 
  @person = Employee.start "Alice"

  puts @person.name
  # => "Alice"
  puts @person.job_title
  # => "Sales assistant"

  @person.promote
  # this will return immediately without blocking
  puts @person.job_title
  # => "Sales manager" (this will block for 0.5s because #job_title query will not start until the #promote command has completed)

  @person.greet_slowly 
  # this will block for 0.2 seconds before returning "H E L L O"

  @person.greet_slowly(ignore_result: true)
  # this will not block and returns nil
```

## Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply just registering for notifications from a single observable, we can build sequences of pipes.  These sequences can filter notifications and route them to different listeners, or merge multiple sources into a single stream of notifications.  

Pipes are implemented as valves, meaning that event notifications can be dispatched asynchronously.  The observer's callback will be triggered from within the pipe's internal context so you should immediately trigger a command on another valve to maintain safety.  

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

[Dispatching events asynchronously (using Fibers)](/spec/examples/pipe_spec.rb):
```ruby
  require "plumbing"
  require "async"

  Plumbing.configure mode: :async 

  Sync do 
    @first_source = Plumbing::Pipe.start 
    @second_source = Plumbing::Pipe.start

    @junction = Plumbing::Junction.start @first_source, @second_source

    @filter = Plumbing::Filter.start source: @junction do |event|
      %w[one-one two-two].include? event.type 
    end

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
