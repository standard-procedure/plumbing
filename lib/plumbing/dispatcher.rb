module Plumbing
  class Dispatcher
    def initialize observers: []
      @observers = observers
    end

    def add_observer observer = nil, &block
      observer ||= block.to_proc
      raise Plumbing::InvalidObserver.new "observer_does_not_respond_to_call" unless observer.respond_to? :call
      @observers << observer
      observer
    end

    def remove_observer observer
      @observers.delete observer
    end

    def is_observer? observer
      @observers.include? observer
    end

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
