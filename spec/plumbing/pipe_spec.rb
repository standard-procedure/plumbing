require "spec_helper"

require "plumbing/pipe"

RSpec.describe Plumbing::Pipe do
  it "pushes an event into the pipe" do
    @event = Plumbing::Event.new type: "test_event", data: {test: "event"}
    @pipe = Plumbing::Pipe.start

    expect { @pipe << @event }.to_not raise_error
  end

  it "only allows events to be pushed" do
    @pipe = Plumbing::Pipe.start

    expect { @pipe << @event }.to raise_error(Plumbing::InvalidEvent)
  end

  it "adds a block observer" do
    @pipe = Plumbing::Pipe.start

    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    expect(@observer).to respond_to(:call)

    @first_event = Plumbing::Event.new type: "test_event", data: {test: "event"}
    @second_event = Plumbing::Event.new type: "test_event", data: {test: "event"}

    @pipe << @first_event
    expect(@results).to eq [@first_event]

    @pipe << @second_event
    expect(@results).to eq [@first_event, @second_event]
  end

  it "adds a callable observer" do
    @pipe = Plumbing::Pipe.start

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @first_event = Plumbing::Event.new type: "test_event", data: {test: "event"}
    @second_event = Plumbing::Event.new type: "test_event", data: {test: "event"}

    @pipe << @first_event
    expect(@results).to eq [@first_event]

    @pipe << @second_event
    expect(@results).to eq [@first_event, @second_event]
  end

  it "does not allow an observer without a #call method" do
    @pipe = Plumbing::Pipe.start
    expect { @pipe.add_observer(Object.new) }.to raise_error(Plumbing::InvalidObserver)
  end

  it "removes an observer" do
    @pipe = Plumbing::Pipe.start

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @first_event = Plumbing::Event.new type: "test_event", data: {test: "event"}
    @second_event = Plumbing::Event.new type: "test_event", data: {test: "event"}

    @pipe << @first_event
    expect(@results).to eq [@first_event]

    @pipe.remove_observer @observer

    @pipe << @second_event
    expect(@results).to eq [@first_event]
  end
end
