require "spec_helper"
require "async"
require "plumbing/fiber/pipe"

RSpec.describe Plumbing::Fiber::Pipe do
  it "pushes an event into the pipe" do
    @pipe = described_class.start

    Sync do
      expect { @pipe.notify "test_event" }.to_not raise_error
    end
  end

  it "only allows events to be pushed" do
    @pipe = described_class.start

    Sync do
      expect { @pipe << @event }.to raise_error(Plumbing::InvalidEvent)
    end
  end

  it "adds a block observer" do
    @pipe = described_class.start

    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    Sync do
      @first_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event]

      @second_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event, @second_event]
    end
  end

  it "adds a callable observer" do
    @pipe = described_class.start

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer
    Sync do
      @first_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event]

      @second_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event, @second_event]
    end
  end

  it "does not allow an observer without a #call method" do
    @pipe = described_class.start

    expect { @pipe.add_observer(Object.new) }.to raise_error(Plumbing::InvalidObserver)
  end

  it "removes an observer" do
    @pipe = described_class.start

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    Sync do
      @first_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event]

      @pipe.remove_observer @observer
      @second_event = @pipe.notify "test_event", test: "event"
      expect(@results).to eq [@first_event]
    end
  end

  it "handles exceptions raised by observers" do
    @pipe = described_class.start

    @failing_observer = @pipe.add_observer do |event|
      raise "Failed processing #{event.type}"
    end
    @results = []

    Sync do
      @working_observer = @pipe.add_observer do |event|
        @results << event
      end

      @event = @pipe.notify "some_event"
      sleep 0.1
      expect(@results.count).to eq 1
    end
  end
end
