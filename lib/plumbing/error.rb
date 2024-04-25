module Plumbing
  class Error < StandardError; end

  # Error raised because an invalid [Event] object was pushed into the pipe
  class InvalidEvent < Error; end

  # Error raised because an invalid observer was registered
  class InvalidObserver < Error; end

  # Error raised because a BlockedPipe was used instead of an actual implementation of a Pipe
  class PipeIsBlocked < Error; end

  # Error raised when chaining pipes and the source pipe is not of the expected type
  class InvalidSource < Error; end
end
