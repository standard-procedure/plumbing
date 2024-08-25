RSpec.shared_examples "an event dispatcher" do |constructor|
  before do
    @dispatcher = constructor.call
  end

  it "adds a block observer" do
    @observer = @dispatcher.add_observer do |event|
      # do something
    end

    expect(@dispatcher.is_observer?(@observer)).to be true
  end

  it "adds a callable observer" do
    @results = []
    @proc = ->(event) { @results << event }
    @dispatcher.add_observer @proc

    expect(@dispatcher.is_observer?(@proc)).to be true
  end

  it "does not allow an observer without a #call method" do
    expect { @dispatcher.add_observer(Object.new) }.to raise_error(Plumbing::InvalidObserver)
  end

  it "removes an observer" do
    @results = []
    @proc = ->(event) { @results << event }
    @dispatcher.add_observer @proc

    @dispatcher.remove_observer @proc
    expect(@dispatcher.is_observer?(@proc)).to be false
  end

  it "notifies block observers" do
    @results = []
    @observer = @dispatcher.add_observer do |event|
      @results << event
    end

    @first_event = Plumbing::Event.new type: "first_event", data: {test: "event"}
    @dispatcher.dispatch @first_event

    expect([@first_event]).to become_equal_to { @results }

    @second_event = Plumbing::Event.new type: "second_event", data: {test: "event"}
    @dispatcher.dispatch @second_event

    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "notifies callable observers" do
    @results = []
    @observer = ->(event) { @results << event }
    @dispatcher.add_observer @observer

    @first_event = Plumbing::Event.new type: "first_event", data: {test: "event"}
    @dispatcher.dispatch @first_event

    expect([@first_event]).to become_equal_to { @results }

    @second_event = Plumbing::Event.new type: "second_event", data: {test: "event"}
    @dispatcher.dispatch @second_event

    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "ensures all observers are notified even if an observer raises an exception" do
    @results = []

    @failing_observer = @dispatcher.add_observer do |event|
      raise "Failed processing #{event.type}"
    end

    @working_observer = @dispatcher.add_observer do |event|
      @results << event
    end

    @event = Plumbing::Event.new type: "event", data: {test: "event"}
    @dispatcher.dispatch @event

    expect([@event]).to become_equal_to { @results }
  end

  it "removes all observers when it shuts down" do
    @observer = ->(event) { event }
    @dispatcher.add_observer @observer

    @dispatcher.shutdown

    expect(@dispatcher.is_observer?(@observer)).to be false
  end
end
