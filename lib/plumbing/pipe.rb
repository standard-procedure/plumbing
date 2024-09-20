module Plumbing
  # A basic pipe
  class Pipe
    include Plumbing::Actor

    async :notify, :remove_observer, :add_observer, :is_observer?, :shutdown

    # Notify observers about an event
    # @param event_name [String] representing the type of event this is
    # @param data [Hash] representing the event-specific data to be passed to the observers
    def notify event_name, **data
      Plumbing.config.logger.debug { "-> #{self.class}#notify #{event_name}" }
      observers.each do |observer|
        Plumbing.config.logger.debug { "===> #{self.class}#dispatch #{event_name} to #{observer}" }
        observer.call event_name, **data
      rescue => ex
        Plumbing.config.logger.error { "!!!! #{self.class}#dispatch #{event_name} => #{ex}" }
        ex
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

    private

    def observers
      @observers ||= []
    end

    require_relative "pipe/filter"
    require_relative "pipe/junction"

  end
end
