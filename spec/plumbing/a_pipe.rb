RSpec.shared_examples "a pipe" do |constructor|
  before do
    @dispatcher = constructor.call
  end

  it "pushes an event into the pipe" do
    @pipe = described_class.start dispatcher: @dispatcher
    @event = Plumbing::Event.new type: "test_event", data: {test: "event"}

    expect { @pipe << @event }.to_not raise_error
  end

  it "only allows events to be pushed" do
    @pipe = described_class.start dispatcher: @dispatcher
    @event = Object.new

    expect { @pipe << @event }.to raise_error(Plumbing::InvalidEvent)
  end

  it "creates an event and pushes it into the pipe" do
    @pipe = described_class.start dispatcher: @dispatcher

    expect { @pipe.notify "test_event", some: "data" }.to_not raise_error
  end

  it "adds a block observer" do
    expect(@dispatcher).to receive(:add_observer) { |&block| expect(block).to_not be_nil }

    @pipe = described_class.start dispatcher: @dispatcher
    @pipe.add_observer { |event| nil }
  end

  it "adds a callable observer" do
    @results = []
    @proc = ->(event) { @results << event }
    expect(@dispatcher).to receive(:add_observer).with(@proc)

    @pipe = described_class.start dispatcher: @dispatcher
    @pipe.add_observer @proc
  end

  it "removes an observer" do
    @pipe = described_class.start dispatcher: @dispatcher
    @proc = ->(event) {}
    expect(@dispatcher).to receive(:remove_observer).with(@proc)

    @pipe.remove_observer @proc
  end

  it "notifies block observers" do
    @pipe = described_class.start dispatcher: @dispatcher

    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    @first_event = @pipe.notify "test_event", test: "event"
    expect([@first_event]).to become_equal_to { @results }

    @second_event = @pipe.notify "test_event", test: "event"
    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "notifies callable observers" do
    @pipe = described_class.start dispatcher: @dispatcher

    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @first_event = @pipe.notify "test_event", test: "event"
    expect([@first_event]).to become_equal_to { @results }

    @second_event = @pipe.notify "test_event", test: "event"
    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "ensures all observers are notified even if an observer raises an exception" do
    @pipe = described_class.start dispatcher: @dispatcher

    @results = []

    @failing_observer = @pipe.add_observer do |event|
      raise "Failed processing #{event.type}"
    end

    @working_observer = @pipe.add_observer do |event|
      @results << event
    end

    @event = @pipe.notify "some_event"
    expect([@event]).to become_equal_to { @results }
  end

  it "shuts down the event dispatcher" do
    @pipe = described_class.start dispatcher: @dispatcher
    expect(@dispatcher).to receive(:shutdown)

    @pipe.shutdown
  end
end
