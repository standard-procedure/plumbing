# frozen_string_literal: true

# ThingHappened is defined in spec/support/events.rb

RSpec.describe Plumbing::Event do
  it "is value-equal on its props" do
    expect(ThingHappened.new(id: "1")).to eq(ThingHappened.new(id: "1"))
  end

  it "distinguishes different prop values" do
    expect(ThingHappened.new(id: "1")).not_to eq(ThingHappened.new(id: "2"))
  end

  it "hashes on its props, so equal events collapse in a Set" do
    set = Set.new([ThingHappened.new(id: "1"), ThingHappened.new(id: "1")])
    expect(set.size).to eq(1)
  end

  it "is frozen / immutable" do
    expect(ThingHappened.new(id: "1")).to be_frozen
  end
end
