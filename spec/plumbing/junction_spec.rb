require "spec_helper"

RSpec.describe Plumbing::Junction do
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
        @junction.add_observer do |event|
          @results << event
        end

        @event = Plumbing::Event.new type: "test_event", data: {test: "event"}
        @source << @event

        expect { @results.include?(@event) }.to become_true
      end

      it "publishes events from two sources" do
        @first_source = Plumbing::Pipe.start
        @second_source = Plumbing::Pipe.start
        @junction = described_class.start @first_source, @second_source

        @results = []
        @junction.add_observer do |event|
          @results << event
        end

        @first_event = Plumbing::Event.new type: "test_event", data: {test: "one"}
        @first_source << @first_event
        expect { @results.include?(@first_event) }.to become_true

        @second_event = Plumbing::Event.new type: "test_event", data: {test: "two"}
        @second_source << @second_event
        expect { @results.include?(@second_event) }.to become_true
      end

      it "publishes events from multiple sources" do
        @first_source = Plumbing::Pipe.start
        @second_source = Plumbing::Pipe.start
        @third_source = Plumbing::Pipe.start
        @junction = described_class.start @first_source, @second_source, @third_source

        @results = []
        @junction.add_observer do |event|
          @results << event
        end

        @first_event = Plumbing::Event.new type: "test_event", data: {test: "one"}
        @first_source << @first_event
        expect { @results.include?(@first_event) }.to become_true

        @second_event = Plumbing::Event.new type: "test_event", data: {test: "two"}
        @second_source << @second_event
        expect { @results.include?(@second_event) }.to become_true

        @third_event = Plumbing::Event.new type: "test_event", data: {test: "three"}
        @third_source << @third_event
        expect { @results.include?(@third_event) }.to become_true
      end
    end
  end
end
