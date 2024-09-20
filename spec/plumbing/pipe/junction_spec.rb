require "spec_helper"

RSpec.describe Plumbing::Pipe::Junction do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "raises a TypeError if it is connected to a non-Pipe" do
        @sources = [Plumbing::Pipe.start, Object.new, Plumbing::Pipe.start]

        expect { described_class.start(*@sources) }.to raise_error(TypeError)
      end

      it "publishes events from a single source" do
        @source = Plumbing::Pipe.start
        @junction = described_class.start @source

        @results = []
        @junction.add_observer do |event_name, **data|
          @results << event_name
        end

        @source.notify "test_event", some: "data"
        expect { @results.include?("test_event") }.to become_true
      end

      it "publishes events from two sources" do
        @first_source = Plumbing::Pipe.start
        @second_source = Plumbing::Pipe.start
        @junction = described_class.start @first_source, @second_source

        @results = []
        @junction.add_observer do |event_name, **data|
          @results << event_name
        end

        @first_source.notify "test_event", some: "data"
        expect { @results.include?("test_event") }.to become_true

        @second_source.notify "another_event", some: "data"
        expect { @results.include?("another_event") }.to become_true
      end

      it "publishes events from multiple sources" do
        @first_source = Plumbing::Pipe.start
        @second_source = Plumbing::Pipe.start
        @third_source = Plumbing::Pipe.start
        @junction = described_class.start @first_source, @second_source, @third_source

        @results = []
        @junction.add_observer do |event_name, **data|
          @results << event_name
        end

        @first_source.notify "first_event", some: "data"
        expect { @results.include?("first_event") }.to become_true

        @second_source.notify "second_event", some: "data"
        expect { @results.include?("second_event") }.to become_true

        @third_source.notify "third_event", some: "data"
        expect { @results.include?("third_event") }.to become_true
      end
    end
  end
end
