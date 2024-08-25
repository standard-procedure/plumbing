require "spec_helper"
require_relative "an_event_dispatcher"

RSpec.describe Plumbing::EventDispatcher do
  it_behaves_like "an event dispatcher", -> { Plumbing::EventDispatcher.new }
end
