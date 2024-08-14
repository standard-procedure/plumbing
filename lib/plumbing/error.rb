module Plumbing
  # Base error class for all Plumbing errors
  class Error < StandardError; end

  # Error raised because a pre-condition failed
  class PreConditionError < Error; end

  # Error raised because a post-condition failed
  class PostConditionError < Error; end

  # Error raised because an invalid [Event] object was pushed into the pipe
  InvalidEvent = Dry::Types::ConstraintError

  # Error raised because an invalid observer was registered
  InvalidObserver = Dry::Types::ConstraintError

  # Error raised because a BlockedPipe was used instead of an actual implementation of a Pipe
  class PipeIsBlocked < Plumbing::Error; end
end
