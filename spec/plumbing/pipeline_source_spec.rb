# frozen_string_literal: true

# ThingHappened is defined in spec/support/events.rb

RSpec.describe Plumbing::Pipeline::Source do
  before { Plumbing::Actor.uses :inline }

  let(:source) { described_class.new }

  def collect(pipeline)
    received = []
    pipeline.observe { |event| received << event }
    received
  end

  describe "push / observe" do
    it "notifies observers of pushed events" do
      received = collect(source)
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(received.map(&:id)).to eq(["1"])
    end

    it "supports the << alias" do
      received = collect(source)
      await { source << ThingHappened.new(id: "1") }
      expect(received.map(&:id)).to eq(["1"])
    end

    it "notifies every observer" do
      a = collect(source)
      b = collect(source)
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(a.size).to eq(1)
      expect(b.size).to eq(1)
    end
  end

  describe "remove / remove_all" do
    it "removes a specific observer" do
      received = []
      observer = await { source.observe { |e| received << e } }
      await { source.remove(observer: observer) }
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(received).to be_empty
    end

    it "removes all observers" do
      a = collect(source)
      b = collect(source)
      await { source.remove_all }
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(a).to be_empty
      expect(b).to be_empty
    end
  end

  describe "debounce" do
    it "coalesces a value-equal event pushed again during notification" do
      received = []
      again = false
      source.observe do |event|
        received << event
        unless again
          again = true
          source.push(event: ThingHappened.new(id: "1"))
        end
      end
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(received.size).to eq(1)
    end

    it "lets a duplicate through when debounce: false" do
      received = []
      again = false
      source.observe do |event|
        received << event
        unless again
          again = true
          source.push(event: ThingHappened.new(id: "1"), debounce: false)
        end
      end
      await { source.push(event: ThingHappened.new(id: "1")) }
      expect(received.size).to eq(2)
    end
  end

  describe "notify (build a registered event by type name)" do
    before { Plumbing::Pipeline.register(ThingHappened) }

    it "builds the registered event from its type name and emits it" do
      received = collect(source)
      await { source.notify(event_type: "ThingHappened", params: {id: "1"}) }
      expect(received.first).to eq(ThingHappened.new(id: "1"))
    end
  end
end
