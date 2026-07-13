# frozen_string_literal: true

# ThingHappened is defined in spec/support/events.rb

RSpec.describe Plumbing::Event do
  it "is value-equal on its props" do
    source = Plumbing::Pipeline.new
    expect(ThingHappened.new(source: source, id: "1")).to eq(ThingHappened.new(source: source, id: "1"))
  end

  it "distinguishes different prop values" do
    source = Plumbing::Pipeline.new
    expect(ThingHappened.new(source: source, id: "1")).not_to eq(ThingHappened.new(source: source, id: "2"))
  end

  it "hashes on its props, so equal events collapse in a Set" do
    source = Plumbing::Pipeline.new
    set = Set.new([ThingHappened.new(source: source, id: "1"), ThingHappened.new(source: source, id: "1")])
    expect(set.size).to eq(1)
  end

  it "is frozen / immutable" do
    source = Plumbing::Pipeline.new
    expect(ThingHappened.new(source: source, id: "1")).to be_frozen
  end
end
