require "spec_helper"

RSpec.describe Plumbing::Pipe::CustomFilter do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "raises a TypeError if it is connected to a non-Pipe" do
        @invalid_source = Object.new

        expect { described_class.start source: @invalid_source }.to raise_error(TypeError)
      end

      it "defines a custom filter" do
        # standard:disable Lint/ConstantDefinitionInBlock
        class ReversingFilter < Plumbing::Pipe::CustomFilter
          def received(event_name, **data) = notify event_name.reverse, **data
        end
        # standard:enable Lint/ConstantDefinitionInBlock

        @pipe = Plumbing::Pipe.start
        @filter = ReversingFilter.start(source: @pipe)
        @result = []
        @filter.add_observer do |event_name, **data|
          @result << event_name
        end

        @pipe.notify "hello"
        @pipe.notify "world"

        expect(@result).to eq ["olleh", "dlrow"]
      end
    end
  end
end
