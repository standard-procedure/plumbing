# frozen_string_literal: true

require_relative "base"

module Plumbing
  class Pipeline
    # A basic origin pipeline: events pushed in are emitted to its observers.
    class Source < Base
    end
  end
end
