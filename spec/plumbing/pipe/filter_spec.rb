require "spec_helper"

RSpec.describe Plumbing::Pipe::Filter do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "raises a TypeError if it is connected to a non-Pipe" do
        @invalid_source = Object.new

        expect { described_class.start source: @invalid_source }.to raise_error(TypeError)
      end

      it "accepts event types" do
        @pipe = Plumbing::Pipe.start

        @filter = described_class.start source: @pipe do |event_name, **data|
          %w[first_type third_type].include? event_name
        end

        @results = []
        @filter.add_observer do |event_name, **data|
          @results << event_name
        end

        @pipe.notify "first_type"
        expect { @results.count }.to become 1

        @pipe.notify "second_type"
        expect { @results.count }.to become 1

        # Use the alternative syntax
        @pipe.notify "third_type"
        expect { @results.count }.to become 2
      end
    end
  end
end
