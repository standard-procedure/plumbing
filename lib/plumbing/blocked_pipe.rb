require_relative "error"
require_relative "event"

module Plumbing
  # The "plumbing" for a Pipe.
  # This class is "blocked", in that it won't push any events to registered observers.
  # Instead, this is the basis for subclasses like [Plumbing::Pipe] which actually allow events to flow through them.
  class BlockedPipe
    # Create a new BlockedPipe
    # Subclasses should call `super()` to ensure the pipe is initialised corrected
    def initialize
      @observers = []
    end

    # Push an event into the pipe
    # @param event [Plumbing::Event] the event to push into the pipe
    # Subclasses should implement this method
    def << event
      raise Plumbing::PipeIsBlocked
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
    def add_observer observer = nil, &block
      observer ||= block.to_proc
      raise Plumbing::InvalidObserver.new "observer_does_not_respond_to_call" unless observer.respond_to? :call
      @observers << observer
    end

    # Remove an observer from this pipe
    # @param observer
    # This removes the given observer from this pipe.  The observer should have previously been returned by #add_observer and is implementation-specific
    def remove_observer observer
      @observers.delete observer
    end

    # Test whether the given observer is observing this pipe
    # @param observer
    # @return [boolean]
    def is_observer? observer
      @observers.include? observer
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
    def self.start(**params)
      new(**params)
    end

    protected

    # Get the next event from the queue
    # @return [Plumbing::Event]
    # Subclasses should implement this method
    def get_next_event
      raise Plumbing::PipeIsBlocked
    end

    # Start the event loop
    # This loop keeps running until `shutdown` is called
    # Some subclasses may need to replace this method to deal with their own specific implementations
    # @param initial_event [Plumbing::Event] optional; the first event in the queue
    def start_run_loop initial_event = nil
      loop do
        event = initial_event || get_next_event
        break if event == :shutdown
        dispatch event
        initial_event = nil
      end
    end

    # Dispatch an event to all observers
    # @param event [Plumbing::Event]
    # Enumerates all observers and `calls` them with this event
    # Discards any errors raised by the observer so that all observers will be successfully notified
    def dispatch event
      @observers.collect do |observer|
        observer.call event
      rescue => ex
        puts ex
        ex
      end
    end
  end
end
