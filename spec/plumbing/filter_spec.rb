require "spec_helper"

require "plumbing/pipe"
require "plumbing/filter"

RSpec.describe Plumbing::Filter do
  it "accepts event types" do
    @pipe = Plumbing::Pipe.start

    @filter = Plumbing::Filter.start(source: @pipe, accepts: %w[first_type third_type])

    @results = []
    @filter.add_observer do |event|
      @results << event
    end

    @pipe << Plumbing::Event.new(type: "first_type")
    expect(@results.count).to eq 1

    @pipe << Plumbing::Event.new(type: "second_type")
    expect(@results.count).to eq 1

    @pipe << Plumbing::Event.new(type: "third_type")
    expect(@results.count).to eq 2
  end

  it "rejects event types" do
    @pipe = Plumbing::Pipe.start

    @filter = Plumbing::Filter.start(source: @pipe, rejects: %w[first_type third_type])

    @results = []
    @filter.add_observer do |event|
      @results << event
    end

    @pipe << Plumbing::Event.new(type: "first_type")
    expect(@results.count).to eq 0

    @pipe << Plumbing::Event.new(type: "second_type")
    expect(@results.count).to eq 1

    @pipe << Plumbing::Event.new(type: "third_type")
    expect(@results.count).to eq 1
  end
end
