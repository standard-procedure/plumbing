require "spec_helper"

RSpec.describe Plumbing::Filter do
  it "raises a Plumbing::InvalidSource if it is connected to a non-Pipe" do
    @invalid_source = Object.new

    expect { described_class.start source: @invalid_source }.to raise_error(Plumbing::InvalidSource)
  end

  it "accepts event types" do
    @pipe = Plumbing::Pipe.start

    @filter = described_class.start source: @pipe do |event|
      %w[first_type third_type].include? event.type.to_s
    end

    @results = []
    @filter.add_observer do |event|
      @results << event
    end

    @pipe << Plumbing::Event.new(type: "first_type", data: nil)
    expect(@results.count).to eq 1

    @pipe << Plumbing::Event.new(type: "second_type", data: nil)
    expect(@results.count).to eq 1

    # Use the alternative syntax
    @pipe.notify "third_type"
    expect(@results.count).to eq 2
  end
end
