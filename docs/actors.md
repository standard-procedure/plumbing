# Plumbing::Actor - safe asynchronous objects

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

The actor model does not eliminate every possible concurrency issue.  If you use `#value` or `await`, it is possible to deadlock yourself.

> Actor A, running in Thread 1, sends a message to Actor B and then awaits the result, meaning Thread 1 is blocked.  Actor B, running in Thread 2, starts to work, but needs to ask Actor A a question.  So it sends a message to Actor A and awaits the result.  Thread 2 is now blocked, waiting for Actor A to respond.  But Actor A, running in Thread 1, is blocked, waiting for Actor B to respond.

This potential deadlock only occurs if you use `#value` or `await` and have actors that call back in to each other.  If your objects are strictly layered, or you never use `#value` or `await` (perhaps, instead using a [Pipe](/docs/pipes.md) to observe events), then this particular deadlock should not occur.  However, just in case, every call to `#value` has a timeout defaulting to 30s.

## How it works

When you call `.start` a proxy if constructed and returned in place of your actual instance.  This proxy has method definitions for each of the methods that are marked as `async`.  As only the  proxy has access to the original instance (the target), this means that no methods apart from your `async` methods are callable from the outside.

The proxy itself is implemented differently for each mode.

### Inline proxy

Each method call is immediately forwarded the target object and any return values wrapped in a temporary object that implements `#value`.  This means that you still need to call `#value` or use `await { ... }` to access return values - so your code stays the same regardless of which mode you are in.

## Async proxy

Using async mode is probably the easiest way to add concurrency to your application, adding "concurrency without parallelism" to your code.

The async proxy uses the async gem to initiate a task for each method call.  The task wraps the return value from the method and callers can `await { ... }` the result.  The tasks are initiated within a semaphore, which is set to `max_concurrency` in the [configuration](/docs/config.md).  Although fibers are cheap, the semaphore is there to trap the number of tasks running out of control (and maybe starving resources such as database connections).

## Threaded proxy

Using threaded (or threaded_rails) mode gives you concurrency and parallelism.  If all your public objects are actors and you are careful about callbacks then the actor model will keep your code safe.

Conceptually, each individual actor has its own thread, isolated from the rest of the world.  However, as threads are part of the operating system and expensive to maintain, the actual implementation simulates this and uses a thread pool.

The threaded proxy, when it receives a method call, creates an internal message object and places that on a queue.  A concurrent-ruby `ScheduledTask` is started (which in turn uses concurrent-ruby's `io` executor and thread pool).  The `ScheduledTask` locks a mutex (to ensure that it is the only thread working for this particular actor), then goes through the queue, dispatching the messages to the target, one at a time.  Once the queue is empty, the task releases the mutex and the thread is placed back into the pool for another actor to use.  Threaded Rails proxies are identical, but they also wrap the task in a call to the Rails Executor, which ensures that no Rails framework code is affected by the actor thread.

But there are a few things to consider.

Firstly, when you pass parameters or return results between threads, those objects are "transported" across the boundaries.

- Most objects are cloned.
- Hashes, keyword arguments and arrays have their contents recursively transported.
- Any object that includes `GlobalID::Identification` (for example, ActiveRecord models) are marshalled into a GlobalID, then un-marshalled back in to their original object on the other side of the boundary (which will cause a database read).

This is to prevent race conditions where the same object from being amended in both the caller and receiver's threads.

Secondly, when you pass a block (or Proc parameter) to another actor, the block/proc will be executed in the **receiver's thread**.

This means that:
- any local or instance variables that are in scope for your block will be unsafe and subject to race conditions, as they have not been transported across the thread boundary
- if you call into another actor, you must not use `await { ... }` or `#value` to access the return values, as that could lead to deadlocks

If you are within an actor and want to access your own instance variables or `#await` another actor's results, you can call `#safely`, which returns you to your own context and the actor's own thread.  This works by posting an internal `perform_safely` message to the actor's queue, so the actual code is run at some point later.

An example: when defining a [custom filter](/docs/pipes.md), both the filter and the pipe that it is observing are actors.  When an event is dispatched, the source triggers the `#received` method on the filter.  This method is called in the source's thread, not the filter's thread.  So, in order to access its own instance variables safely, the filter calls `#safely` which adds a `perform_safely` message to the filter's queue and, when the filter's thread is ready, the contents of the `safely` block are executed.

```ruby
class EveryThirdEvent < Plumbing::CustomFilter
  def initialize source:
    super
    @events = []
  end

  def received event_name, **
    safely do
      @events << event_name
      if @events.count >= 3
        @events.clear
        self.notify event_data, **
      end
    end
  end
end
```

## Constructing actors

Instead of constructing your object with `.new`, use `.start`.  This builds the proxy object that wraps the target instance and dispatches messages.  Only messages that have been defined as part of the actor are available in this proxy - so you don't have to worry about callers bypassing the actor's internal context.

## Referencing actors

If you're within a method inside your actor and you want to pass a reference to yourself, instead of using `self`, you should use `proxy` (which is also aliased as `as_actor` or `async`).

Also be aware that if you use actors in one place, you need to use them everywhere - especially if you're using threads.  This is because as the actor sends messages to its collaborators, those calls will be made from within the actor's internal context.  If the collaborators are also actors, the subsequent messages will be handled correctly, if not, data consistency bugs could occur.  This does not mean that every class needs to be an actor, just your "public API" classes which may be accessed from multiple actors or other threads.

## Usage

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

## Writing tests

As soon as you're working in :async or :threaded mode, you'll find your tests become unpredictable.

To help with this there are some helpers that you can include in your code.

Firstly, you can wait for something to become true.  The `#wait_for` method is added into `Kernel` so it is available everywhere.  It repeatedly executes the given block until a truthy value is returned or the timeout is reached (at which point it raises a Timeout::Error). Note that you still need to use `await` (or call `#value`) to access return values from messages sent to actors.

```ruby
@target = SomeActor.start
@subject = SomeOtherActor.start

@subject.do_something_to @target

wait_for do
  await { @target.was_updated? }
end
```

Secondly, if you're using RSpec, you can `require "plumbing/spec/become_matchers"` to add some extra expectation matchers.  These matchers use `wait_for` to repeatedly evaluate the given block until it reaches the expected value or times out.  The matchers are `become(value)`, `become_true`, `become_false`, `become_truthy` and `become_falsey`.  Note that you still need to use `await` (or call `#value`) to access return values from messages sent to actors.

```ruby
@target = SomeActor.start
@subject = SomeOtherActor.start

@subject.do_something_to @target

expect { @target.was_updated?.value }.to become_true

@employee = Employee.start

expect { @employee.job_title.value }.to become "Sales assistant"

@employee.promote!

expect { @employee.job_title.value }.to become "Manager"
```

Thirdly, if you want to test your code in all modes, you can wrap your specs in a call to `Plumbing::Spec.modes`.

```ruby
RSpec.describe MyClass do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "does this"
      it "does that"
    end
  end
end
```

