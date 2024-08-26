require "spec_helper"

RSpec.describe Plumbing::CustomFilter do
  it "raises a TypeError if it is connected to a non-Pipe" do
    @invalid_source = Object.new

    expect { described_class.start source: @invalid_source }.to raise_error(TypeError)
  end

  it "defines a custom filter" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class ReversingFilter < Plumbing::CustomFilter
      def received(event) = notify event.type.reverse, event.data
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    @pipe = Plumbing::Pipe.start
    @filter = ReversingFilter.new(source: @pipe)
    @result = []
    @filter.add_observer do |event|
      @result << event.type
    end

    @pipe.notify "hello"
    @pipe.notify "world"

    expect(@result).to eq ["olleh", "dlrow"]
  end
end
