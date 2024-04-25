if RUBY_ENGINE != "opal"
  require "spec_helper"

  require "plumbing/concurrent/pipe"

  RSpec.describe Plumbing::Concurrent::Pipe do
    it "pushes an event into the pipe" do
      @pipe = described_class.start

      expect { @pipe.notify "test_event" }.to_not raise_error
    ensure
      @pipe.shutdown
    end

    it "only allows events to be pushed" do
      @pipe = described_class.start

      expect { @pipe << Object.new }.to raise_error(Plumbing::InvalidEvent)
    ensure
      @pipe.shutdown
    end

    it "does not allow block observers" do
      @pipe = described_class.start

      expect do
        @pipe.add_observer do |event|
          @results << event
        end
      end.to raise_error(Plumbing::InvalidObserver)
    ensure
      @pipe.shutdown
    end

    it "does not allow callable observers" do
      @pipe = described_class.start

      @results = []
      @observer = ->(event) { @results << event }
      expect { @pipe.add_observer @observer }.to raise_error(Plumbing::InvalidObserver)
    ensure
      @pipe.shutdown
    end

    it "does not allow non-Ractor observers" do
      @pipe = described_class.start

      expect { @pipe.add_observer(Object.new) }.to raise_error(Plumbing::InvalidObserver)
    ensure
      @pipe.shutdown
    end

    it "removes an observer" do
      @pipe = described_class.start

      @results = []
      @ractor = Ractor.new do
        Ractor.yield Ractor.receive
      end
      @pipe.add_observer @ractor

      @pipe.notify "first_event"
      expect(@ractor.take.type).to eq "first_event"

      @pipe.remove_observer @ractor
      expect(@pipe.is_observer?(@ractor)).to eq false
    ensure
      @pipe.shutdown
    end

    it "handles exceptions raised by observers" do
      report_on_exception = Thread.report_on_exception
      Thread.report_on_exception = false
      @pipe = described_class.start

      @failing_ractor = Ractor.new do
        raise "Failed processing #{Ractor.receive}"
      end
      @failing_observer = @pipe.add_observer @failing_ractor

      @working_ractor = Ractor.new do
        Ractor.yield Ractor.receive
      end
      @working_observer = @pipe.add_observer @working_ractor

      @event = @pipe.notify "some_event"
      expect { @failing_observer.take }.to raise_error(Ractor::RemoteError)
      expect(@working_observer.take.type).to eq "some_event"
    ensure
      @pipe.shutdown
      Thread.report_on_exception = report_on_exception
    end

    it "shuts down, ends the internal ractor and ends all observers" do
      @pipe = described_class.start

      @ractor = Ractor.new do
        Ractor.yield Ractor.receive
      end
      @observer = @pipe.add_observer @ractor

      @pipe.shutdown

      expect { @pipe.notify "some_event" }.to raise_error(Ractor::ClosedError)
    end
  end
end
