module Plumbing
  # A basic pipe
  class Pipe
    include Plumbing::Actor

    async :notify, :<<, :remove_observer, :add_observer, :is_observer?, :shutdown

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
      Plumbing.config.logger.debug { "-> #{@self.class}#notify #{event_type}" }
      Event.new(type: event_type, data: data).tap do |event|
        self << event
      end
    end

    # Add an observer to this pipe
    # Either a `callable` or a `block` must be supplied.  If the latter, it is converted to a [Proc]
    # @param callable [#call] (optional)
    # @param &block [Block] (optional)
    # @return [#call]
    def add_observer(observer = nil, &block)
      observer ||= block.to_proc
      observers << observer.as(Callable).target
      observer
    end

    # Remove an observer from this pipe
    # @param observer [#call] remove the observer from this pipe (where the observer was previously added by #add_observer)
    def remove_observer observer
      observers.delete observer
    end

    # Test whether the given observer is observing this pipe
    # @param [#call] observer
    # @return [Boolean]
    def is_observer? observer
      observers.include? observer
    end

    # Close this pipe and perform any cleanup.
    # Subclasses should override this to perform their own shutdown routines and call `super` to ensure everything is tidied up
    def shutdown
      observers.clear
      stop
    end

    protected

    # Dispatch an event to all observers
    # @param event [Plumbing::Event]
    # Enumerates all observers and `calls` them with this event
    # Discards any errors raised by the observer so that all observers will be successfully notified
    def dispatch event
      observers.each do |observer|
        Plumbing.config.logger.debug { "===> #{self.class}#dispatch #{event.type} to #{observer}" }
        observer.call event
      rescue => ex
        puts ex
        ex
      end
    end

    def observers
      @observers ||= []
    end
  end
end
