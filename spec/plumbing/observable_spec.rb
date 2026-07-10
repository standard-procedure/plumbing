# frozen_string_literal: true

require "plumbing/observable"

RSpec.describe Plumbing::Observable do
  # A plain object (deliberately NOT an actor) that broadcasts through the
  # module — push/notify are private, so expose them via public wrappers.
  let(:broadcaster_class) do
    Class.new do
      include Plumbing::Observable

      def announce(event) = push(event)
      def announce_type(name, **params) = notify(name, **params)
    end
  end
  subject(:broadcaster) { broadcaster_class.new }

  it "delivers a pushed event to a registered observer" do
    events = []
    broadcaster.observe { |event| events << event }

    broadcaster.announce(ThingHappened.new(source: broadcaster, id: "1"))

    expect(events).to eq [ThingHappened.new(source: broadcaster, id: "1")]
  end

  it "delivers to every registered observer" do
    a = []
    b = []
    broadcaster.observe { |event| a << event }
    broadcaster.observe { |event| b << event }

    broadcaster.announce(ThingHappened.new(source: broadcaster, id: "1"))

    expect(a).to eq [ThingHappened.new(source: broadcaster, id: "1")]
    expect(b).to eq [ThingHappened.new(source: broadcaster, id: "1")]
  end

  it "builds and delivers a registered event via notify" do
    Plumbing::Pipeline.register(ThingHappened)
    events = []
    broadcaster.observe { |event| events << event }

    broadcaster.announce_type("ThingHappened", id: "7")

    expect(events).to eq [ThingHappened.new(source: broadcaster, id: "7")]
  end

  it "stops delivering to a removed observer" do
    events = []
    observer = broadcaster.observe { |event| events << event }.await
    broadcaster.remove(observer)

    broadcaster.announce(ThingHappened.new(source: broadcaster, id: "1"))

    expect(events).to be_empty
  end

  it "removes all observers" do
    events = []
    broadcaster.observe { |event| events << event }
    broadcaster.remove_all

    broadcaster.announce(ThingHappened.new(source: broadcaster, id: "1"))

    expect(events).to be_empty
  end

  it "is a safe no-op to emit when nothing is observing" do
    expect { broadcaster.announce(ThingHappened.new(source: broadcaster, id: "1")) }.not_to raise_error
  end
end
