# frozen_string_literal: true

RSpec.describe Plumbing::Actor::Observable do
  it "notifies observers when something changes" do
    observable_class = Class.new do
      include Plumbing::Actor
      include Plumbing::Actor::Observable

      prop :name, String

      async :say do
        param :words, String

        calls do |words:|
          push event: ThingHappened.new(source: self, id: "#{words} #{@name}")
        end
      end

      async :shout do
        param :words, String

        calls do |words:|
          notify "ThingHappened", id: "#{words} #{@name}".upcase
        end
      end
    end

    events = []
    Plumbing::Event.types.register ThingHappened

    observable = observable_class.new(name: "Alice")
    observable.add_observer do |event|
      events << event
    end

    await { observable.say words: "Hello" }
    await { observable.shout words: "boom" }
    await { observable.say words: "Goodbye" }

    expect(events.size).to eq 3
    expect(events[0].id).to eq "Hello Alice"
    expect(events[1].id).to eq "BOOM ALICE"
    expect(events[2].id).to eq "Goodbye Alice"
  end
end
