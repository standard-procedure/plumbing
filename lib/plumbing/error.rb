module Plumbing
  # Base error class for all Plumbing errors
  class Error < StandardError; end

  # Error raised because a pre-condition failed
  class PreConditionError < Error; end

  # Error raised because a post-condition failed
  class PostConditionError < Error; end

  # Error raised because an invalid [Event] object was pushed into the pipe
  class InvalidEvent < Error; end
end
