module Plumbing
  class EventDispatcher
    def initialize observers: []
      @observers = observers.as(Collection)
    end

    def add_observer observer = nil, &block
      observer ||= block.to_proc
      @observers << observer.as(Callable).target
      observer
    end

    def remove_observer observer
      @observers.delete observer
    end

    def is_observer? observer
      @observers.include? observer
    end

    def dispatch event
      @observers.each do |observer|
        observer.call event
      rescue => ex
        puts ex
        ex
      end
    end

    def shutdown
      @observers = []
    end
  end
end
