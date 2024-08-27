RSpec.shared_examples "a pipe" do
  it "adds a block observer" do
    @pipe = described_class.start
    @observer = @pipe.add_observer do |event|
      puts event.type
    end
    expect(@pipe.is_observer?(@observer)).to eq true
  end

  it "adds a callable observer" do
    @pipe = described_class.start
    @proc = ->(event) { puts event.type }

    @pipe.add_observer @proc

    expect(@pipe.is_observer?(@proc)).to eq true
  end

  it "does not allow an observer without a #call method" do
    @pipe = described_class.start

    expect { @pipe.add_observer(Object.new) }.to raise_error(TypeError)
  end

  it "removes an observer" do
    @pipe = described_class.start
    @proc = ->(event) { puts event.type }

    @pipe.remove_observer @proc

    expect(@pipe.is_observer?(@proc)).to eq false
  end

  it "does not send notifications for objects  which are not events" do
    @pipe = described_class.start
    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    @pipe << Object.new

    sleep 0.5
    expect(@results).to eq []
  end

  it "notifies block observers" do
    @pipe = described_class.start
    @results = []
    @observer = @pipe.add_observer do |event|
      @results << event
    end

    @first_event = Plumbing::Event.new type: "first_event", data: {test: "event"}
    @second_event = Plumbing::Event.new type: "second_event", data: {test: "event"}

    @pipe << @first_event
    expect([@first_event]).to become_equal_to { @results }

    @pipe << @second_event
    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "notifies callable observers" do
    @pipe = described_class.start
    @results = []
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @first_event = Plumbing::Event.new type: "first_event", data: {test: "event"}
    @second_event = Plumbing::Event.new type: "second_event", data: {test: "event"}

    @pipe << @first_event
    expect([@first_event]).to become_equal_to { @results }

    @pipe << @second_event
    expect([@first_event, @second_event]).to become_equal_to { @results }
  end

  it "ensures all observers are notified even if an observer raises an exception" do
    @pipe = described_class.start
    @results = []
    @failing_observer = @pipe.add_observer do |event|
      raise "Failed processing #{event.type}"
    end
    @working_observer = @pipe.add_observer do |event|
      @results << event
    end

    @event = Plumbing::Event.new type: "event", data: {test: "event"}

    @pipe << @event

    expect([@event]).to become_equal_to { @results }
  end

  it "shuts down the pipe" do
    @pipe = described_class.start
    @observer = ->(event) { @results << event }
    @pipe.add_observer @observer

    @pipe.shutdown

    expect(@pipe.is_observer?(@observer)).to eq false
  end
end
