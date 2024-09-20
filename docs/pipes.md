# Plumbing::Pipe - a composable observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

[Plumbing::Pipe](lib/plumbing/pipe.rb) makes observers "composable".  Instead of simply just registering for notifications from a single observable, we can build sequences of pipes.  These sequences can filter notifications and route them to different listeners, or merge multiple sources into a single stream of notifications.

Pipes are implemented as [actors](/docs/actors.md), meaning that event notifications can be dispatched asynchronously.  The observer's callback will be triggered from within the pipe's internal context so you should immediately trigger a command on another actor to maintain safety.

Also take a look at [pipes vs pipelines](/docs/pipes_vs_pipelines.md).

## Usage

[A simple observer](/spec/examples/pipe_spec.rb):
```ruby
@source = Plumbing::Pipe.start

@result = []
@source.add_observer do |event_name, **data|
  @result << event_name
end

@source.notify "something_happened", message: "But what was it?"
expect(@result).to eq ["something_happened"]
```

[Simple filtering](/spec/examples/pipe_spec.rb):
```ruby
@source = Plumbing::Pipe.start

@filter = Plumbing::Pipe::Filter.start source: @source do |event_name, **data|
  %w[important urgent].include? event_name
end

@result = []
@filter.add_observer do |event_name, **data|
  @result << event_name
end

@source.notify "important", message: "ALERT! ALERT!"
expect(@result).to eq ["important"]

@source.notify "unimportant", message: "Nothing to see here"
expect(@result).to eq ["important"]
```

[Custom filtering](/spec/examples/pipe_spec.rb):
```ruby
# standard:disable Lint/ConstantDefinitionInBlock
class EveryThirdEvent < Plumbing::Pipe::CustomFilter
  def initialize source:
    super
    @events = []
  end

  def received event_name, **data
    safely do
      @events << event_name
      if @events.count >= 3
        @events.clear
        notify event_name, **data
      end
    end
  end
end
# standard:enable Lint/ConstantDefinitionInBlock

@source = Plumbing::Pipe.start
@filter = EveryThirdEvent.start(source: @source)

@result = []
@filter.add_observer do |event_name, **data|
  @result << event_name
end

1.upto 10 do |i|
  @source.notify i.to_s
end

expect(@result).to eq ["3", "6", "9"]
```

[Joining multiple sources](/spec/examples/pipe_spec.rb):
```ruby
@first_source = Plumbing::Pipe.start
@second_source = Plumbing::Pipe.start

@junction = Plumbing::Pipe::Junction.start @first_source, @second_source

@result = []
@junction.add_observer do |event_name, **data|
  @result << event_name
end

@first_source.notify "one"
expect(@result).to eq ["one"]
@second_source.notify "two"
expect(@result).to eq ["one", "two"]
```
