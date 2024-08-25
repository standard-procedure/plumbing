require "spec_helper"
require_relative "a_pipe"
require "async"

RSpec.describe Plumbing::Pipe do
  context "synchronously dispatching events" do
    it_behaves_like "a pipe", -> { Plumbing::Dispatcher.new }
  end

  context "dispatching events with fibers" do
    require_relative "../../lib/plumbing/dispatcher/fiber"
    around :example do |example|
      Sync(&example)
    end

    it_behaves_like "a pipe", -> { Plumbing::Dispatcher::Fiber.new }

    it "debounces duplicate events" do
      @dispatcher = Plumbing::Dispatcher::Fiber.new
      @pipe = described_class.start dispatcher: @dispatcher
      @first_event = Plumbing::Event.new type: "first", data: {test: "event"}
      @second_event = Plumbing::Event.new type: "second", data: {test: "event"}

      @results = []
      @observer = ->(event) { @results << event }
      @pipe.add_observer @observer

      # Pause the dispatcher to prevent timing errors when the spec is running
      @dispatcher.pause
      @pipe << @first_event
      @pipe << @first_event
      @pipe << @second_event
      @pipe << @first_event
      @pipe << @second_event
      @dispatcher.resume

      expect([@first_event, @second_event]).to become_equal_to { @results }

      # Check that subsequent events are processed and not debounced
      @pipe << @first_event
      @pipe << @second_event

      expect([@first_event, @second_event, @first_event, @second_event]).to become_equal_to { @results }
    end
  end
end
