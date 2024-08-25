module Plumbing
  # A basic pipe
  class Pipe
    require_relative "dispatcher"

    # Subclasses should call `super()` to ensure the pipe is initialised corrected
    def initialize dispatcher: nil
      @dispatcher = dispatcher || Dispatcher.new
    end

    # Push an event into the pipe
    # @param event [Plumbing::Event] the event to push into the pipe
    def << event
      raise Plumbing::InvalidEvent.new event unless event.is_a? Plumbing::Event
      dispatch event
    end

    # A shortcut to creating and then pushing an event
    # @param event_type [String] representing the type of event this is
    # @param data [Hash] representing the event-specific data to be passed to the observers
    def notify event_type, data = nil
      Event.new(type: event_type, data: data).tap do |event|
        self << event
      end
    end

    # Add an observer to this pipe
    # @param callable [Proc] (optional)
    # @param &block [Block] (optional)
    # @return an object representing this observer (dependent upon the implementation of the pipe itself)
    # Either a `callable` or a `block` must be supplied.  If the latter, it is converted to a [Proc]
    def add_observer(observer = nil, &)
      @dispatcher.add_observer(observer, &)
    end

    # Remove an observer from this pipe
    # @param observer
    # This removes the given observer from this pipe.  The observer should have previously been returned by #add_observer and is implementation-specific
    def remove_observer observer
      @dispatcher.remove_observer observer
    end

    # Test whether the given observer is observing this pipe
    # @param observer
    # @return [boolean]
    def is_observer? observer
      @dispatcher.is_observer? observer
    end

    # Close this pipe and perform any cleanup.
    # Subclasses should override this to perform their own shutdown routines and call `super` to ensure everything is tidied up
    def shutdown
      # clean up and release any observers, just in case
      @observers = []
    end

    # Start this pipe
    # Subclasses may override this method to add any implementation specific details.
    # By default any supplied parameters are called to the subclass' `initialize` method
    def self.start(*, **, &)
      new(*, **, &)
    end

    protected

    # Dispatch an event to all observers
    # @param event [Plumbing::Event]
    # Enumerates all observers and `calls` them with this event
    # Discards any errors raised by the observer so that all observers will be successfully notified
    def dispatch event
      @dispatcher.dispatch event
    end
  end
end
