# frozen_string_literal: true

require "dry/types"
module Plumbing
  class Error < StandardError; end

  require_relative "plumbing/version"

  require_relative "plumbing/event"
  require_relative "plumbing/pipe"
end
