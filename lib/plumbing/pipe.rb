module Plumbing
  # An implementation of a pipe that uses Fibers
  class Pipe < BlockedPipe
    def initialize
      super
      @fiber = Fiber.new do |initial_event|
        start_run_loop initial_event
      end
    end

    def << event
      raise Plumbing::InvalidEvent.new "event is not a Plumbing::Event" unless event.is_a? Plumbing::Event
      @fiber.resume event
    end

    def shutdown
      super
      @fiber.resume :shutdown
    end

    protected

    def get_next_event
      Fiber.yield
    end
  end
end
