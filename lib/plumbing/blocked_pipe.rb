require "dry/types"
require_relative "error"
require_relative "event"

module Plumbing
  # Error raised because an invalid [Event] object was pushed into the pipe
  InvalidEvent = Dry::Types::ConstraintError
  # Error raised because an invalid observer was registered
  InvalidObserver = Dry::Types::ConstraintError
  # Error raised because a BlockedPipe was used instead of an actual implementation of a Pipe
  class PipeIsBlocked < Plumbing::Error; end

  # The "plumbing" for a Pipe.
  # This class is "blocked", in that it won't push any events to registered observers.
  # Instead, this is the basis for subclasses like [Plumbing::Pipe] which actually allow events to flow through them.
  class BlockedPipe
    module Types
      include Dry::Types()
      # Events must be Plumbing::Event instances or subclasses
      Event = Instance(Plumbing::Event)
      # Observers must have a `call` method
      Observer = Interface(:call)
    end

    # Create a new BlockedPipe
    # Subclasses should call `super()` to ensure the pipe is initialised corrected
    def initialize
      @observers = []
    end

    # Push an event into the pipe
    # @param event [Plumbing::Event] the event to push into the pipe
    # Subclasses should implement this method
    def << event
      raise PipeIsBlocked
    end

    # A shortcut to creating and then pushing an event
    # @param event_type [String] representing the type of event this is
    # @param data [Hash] representing the event-specific data to be passed to the observers
    def notify event_type, **data
      Event.new(type: event_type, data: data).tap do |event|
        self << event
      end
    end

    # Add an observer to this pipe
    # @param callable [Proc] (optional)
    # @param &block [Block] (optional)
    # @return an object representing this observer (dependent upon the implementation of the pipe itself)
    # Either a `callable` or a `block` must be supplied.  If the latter, it is converted to a [Proc]
    def add_observer callable = nil, &block
      callable ||= block.to_proc
      Types::Observer[callable].tap do |observer|
        @observers << observer
      end
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
      raise PipeIsBlocked
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
