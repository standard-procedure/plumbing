require_relative "blocked_pipe"

module Plumbing
  # An implementation of a pipe that uses Fibers
  class Pipe < BlockedPipe
    def << event
      raise InvalidEvent.new("Event is not a Plumbing::Event") unless Plumbing::Event === event
      dispatch event
    end
  end
end
