require "spec_helper"

RSpec.describe Plumbing::Filter do
  it "accepts event types" do
    @pipe = Plumbing::Pipe.start

    @filter = Plumbing::Filter.start source: @pipe do |event|
      puts event.inspect

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
