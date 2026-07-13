# frozen_string_literal: true

RSpec.describe Plumbing::Event::Types do
  describe "registration" do
    after do
      Plumbing::Event.types.remove_all
    end

    it "builds an event from the given parameters" do
      Plumbing::Event.types.register ThingHappened

      source = Plumbing::Pipeline.new

      event = await { Plumbing::Event.types.build "ThingHappened", source: source, id: "1" }
      expect(event).to be_kind_of ThingHappened
      expect(event.source).to eq source
      expect(event.id).to eq "1"
    end

    it "builds an event using an alternative event type name" do
      Plumbing::Event.types.register ThingHappened, name: "what_is_it"

      source = Plumbing::Pipeline.new

      event = await { Plumbing::Event.types.build "what_is_it", source: source, id: "1" }
      expect(event).to be_kind_of ThingHappened
      expect(event.source).to eq source
      expect(event.id).to eq "1"
    end

  end
end
