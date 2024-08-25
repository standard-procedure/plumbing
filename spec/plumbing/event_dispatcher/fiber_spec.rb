require "spec_helper"
require_relative "../an_event_dispatcher"
require_relative "../../../lib/plumbing/event_dispatcher/fiber"

RSpec.describe Plumbing::EventDispatcher::Fiber do
  around :example do |example|
    Sync(&example)
  end

  it_behaves_like "an event dispatcher", -> { Plumbing::EventDispatcher::Fiber.new }

  it "removes all events from the queue when it shuts down" do
    @dispatcher = Plumbing::EventDispatcher::Fiber.new
    @dispatcher.pause
    @dispatcher.dispatch Plumbing::Event.new(type: "test_event", data: nil)

    @dispatcher.shutdown
    expect(@dispatcher.queue_size).to eq 0
  end
end
