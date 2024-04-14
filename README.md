# Plumbing

Composable Observer

[Observers](https://ruby-doc.org/3.3.0/stdlibs/observer/Observable.html) in Ruby are a pattern where objects (observers) register their interest in another object (the observable).  This pattern is common throughout programming languages (event listeners in Javascript, the dependency protocol in [Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

Unlike ruby's in-built observers, this gem makes observers "composable".  Instead of simply registering for notifications from the observable, we observe a stream of notifications, which could be produced by multiple observables, all being sent through the same pipe.  We can then chain observers together, composing a "pipeline" of operations from a single source of events.

For example, in a social-networking application, you may push all events associated with a user through a single pipe.  But one module within the application is only interested in follow requests, another module in comments.  So the "followers" module would attach a "filter pipe" to the "users" pipe, filtering out everything except follow requests.  Then the code within that module observes this "filter pipe" so only gets notified about follow requests.  And similarly, the "comments" module attaches a "filter pipe" to the "users" pipe, filtering out everything except "comments".

However, the pipeline can do much more than simple filtering.

In a search engine application, it is important to keep a record of what has been searched for, but more importantly, which of those search results resulted in a click - as you can then use this data to improve your search results in future.  We could implement a chain of observers, from the pipe that records all search related events, a filter that looks at the events from a single user, to another observer that maintains a log of every search result for a given user from the last 30 minutes and then matches any clicks to those results - sending those matches to an analytics service.

The key fact is that each element in the chain of observers is only aware of the stream of events from the element just before it.  And when it outputs its own events, any observers to that stream are only aware of the element they have subscribed to.  This means that the chain works in a similar manner to unix pipes.

In unix, you can use `cat logfile | grep -o "some text" | ec -l` to easily count the number of times "some text" occurs in your logfile.  Each individual command in that pipeline is extremely simple and optimised for its one task.  But piping them together gives you incredible flexibility and power.

The same is true when you compose a pipeline of observers, each of which watches the events in a stream.  You can attach observers which buffer the incoming events, so the receivers aren't swamped.  You can attach observers which manipulate the incoming data (see the inline emoji writer in the examples folder), or de-duplicate or merge events (which is very useful if you want to prevent flicker and unnecessary redraws in your user-interface).  And observers can republish events to different streams - we could take events on one stream and send those same events, or a subset, to a web-socket.


## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

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
