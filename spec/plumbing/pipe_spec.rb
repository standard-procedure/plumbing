require "spec_helper"

RSpec.describe Plumbing::Pipe do
  it "pushes an event into the pipe" do
    @pipe = described_class.start

    expect { @pipe.notify "test_event" }.to_not raise_error
  end

  it "only allows events to be pushed" do
    @pipe = described_class.start

    expect { @pipe << @event }.to raise_error(Plumbing::InvalidEvent)
  end

  it "adds a block observer" do
    @pipe = described_class.start

    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    @first_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event]

    @second_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event, @second_event]
  end

  it "adds a callable observer" do
    @pipe = described_class.start

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @first_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event]

    @second_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event, @second_event]
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

    @first_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event]

    @pipe.remove_observer @observer
    @second_event = @pipe.notify "test_event", test: "event"
    expect(@results).to eq [@first_event]
  end

  it "handles exceptions raised by observers" do
    @pipe = described_class.start

    @failing_observer = @pipe.add_observer do |event|
      raise "Failed processing #{event.type}"
    end
    @results = []
    @working_observer = @pipe.add_observer do |event|
      @results << event
    end

    @event = @pipe.notify "some_event"
    expect(@results.count).to eq 1
  end

  it "shuts down, ends the internal fiber and releases all observers" do
    @pipe = described_class.start

    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    @pipe.shutdown
    expect { @pipe.notify "some_event" }.to raise_error(FiberError)
  end
end
