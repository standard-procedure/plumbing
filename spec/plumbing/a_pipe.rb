RSpec.shared_examples "a pipe" do
  it "adds a block observer" do
    @pipe = described_class.start
    @observer = await do
      @pipe.add_observer do |event_name, data|
        puts event_name
      end
    end
    expect(await { @pipe.is_observer?(@observer) }).to eq true
  end

  it "adds a callable observer" do
    @pipe = described_class.start
    @proc = ->(event_name, data) { puts event_name }

    @pipe.add_observer @proc

    expect(await { @pipe.is_observer?(@proc) }).to eq true
  end

  it "does not allow an observer without a #call method" do
    @pipe = described_class.start

    expect { await { @pipe.add_observer(Object.new) } }.to raise_error(TypeError)
  end

  it "removes an observer" do
    @pipe = described_class.start
    @proc = ->(event_name, data) { puts event_name }

    @pipe.remove_observer @proc

    expect(await { @pipe.is_observer?(@proc) }).to eq false
  end

  it "notifies block observers" do
    @pipe = described_class.start
    @results = []
    @observer = @pipe.add_observer do |event_name, data|
      @results << event_name
    end

    @pipe.notify "first_event", test: "event"
    expect { @results.include?("first_event") }.to become_true

    @pipe.notify "second_event", some: :data
    expect { @results.include?("second_event") }.to become_true
  end

  it "notifies callable observers" do
    @pipe = described_class.start
    @results = []
    @observer = ->(event_name, data) { @results << event_name }
    @pipe.add_observer @observer

    @pipe.notify "first_event", test: "event"
    expect { @results.include?("first_event") }.to become_true

    @pipe.notify "second_event", some: :data
    expect { @results.include?("second_event") }.to become_true
  end

  it "ensures all observers are notified even if an observer raises an exception" do
    @pipe = described_class.start
    @results = []
    @failing_observer = @pipe.add_observer do |event_name, data|
      raise "Failed processing #{event_name}"
    end
    @working_observer = @pipe.add_observer do |event_name, data|
      @results << event_name
    end

    @pipe.notify "some_event"

    expect { @results.include?("some_event") }.to become_true
  end

  it "shuts down the pipe" do
    @pipe = described_class.start
    @results = []
    @observer = ->(event_name, data) { @results << event_name }
    @pipe.add_observer @observer

    @pipe.shutdown
    @pipe.notify "ignore_me"
    sleep 0.2
    expect { @results.empty? }.to become_true
  end
end
