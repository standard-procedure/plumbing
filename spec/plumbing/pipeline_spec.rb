# frozen_string_literal: true

# ThingHappened is defined in spec/support/events.rb

RSpec.describe Plumbing::Pipeline do
  before { Plumbing::Actor.uses :inline }

  let(:source) { described_class.new }

  def collect(pipeline)
    received = []
    pipeline.add_observer { |event| received << event }
    received
  end

  describe "observe and push" do
    it "notifies observers of pushed events" do
      received = collect(source)
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(received.map(&:id)).to eq(["1"])
    end

    it "supports the << alias" do
      received = collect(source)
      await { source << ThingHappened.new(source: source, id: "1") }
      expect(received.map(&:id)).to eq(["1"])
    end

    it "notifies every observer" do
      a = collect(source)
      b = collect(source)
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(a.size).to eq(1)
      expect(b.size).to eq(1)
    end
  end

  describe "notify" do
    before { Plumbing::Event.types.register(ThingHappened) }

    it "builds the registered event from its type name and emits it" do
      received = collect(source)

      source.notify("ThingHappened", id: "1")

      expect(received.first).to eq(ThingHappened.new(source: source, id: "1"))
    end

    it "allows the source of the new event to be overridden" do
      alternative = Plumbing::Pipeline::Junction.new(source)
      received = collect(source)

      source.notify("ThingHappened", source: alternative, id: "1")

      expect(received.first).to eq(ThingHappened.new(source: alternative, id: "1"))
    end
  end


  describe "remove_observer / remove_all_observers" do
    it "removes a specific observer" do
      received = []

      observer = await { source.add_observer { |e| received << e } }
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(received.size).to eq 1

      await { source.remove_observer(observer: observer) }
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(received.size ).to eq 1
    end

    it "removes all observers" do
      a = collect(source)
      b = collect(source)
      await { source.remove_all_observers }
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(a).to be_empty
      expect(b).to be_empty
    end
  end

  describe "debounce" do
    it "coalesces a value-equal event pushed again during notification" do
      received = []
      again = false
      source.add_observer do |event|
        received << event
        unless again
          again = true
          source.push(event: ThingHappened.new(source: source, id: "1"))
        end
      end
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(received.size).to eq(1)
    end

    it "lets a duplicate through when debounce: false" do
      received = []
      again = false
      source.add_observer do |event|
        received << event
        unless again
          again = true
          source.push(event: ThingHappened.new(source: source, id: "1"), debounce: false)
        end
      end
      await { source.push(event: ThingHappened.new(source: source, id: "1")) }
      expect(received.size).to eq(2)
    end
  end

end
