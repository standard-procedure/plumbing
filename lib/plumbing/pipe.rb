require_relative "blocked_pipe"

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
      @fiber.resume Types::Event[event]
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
