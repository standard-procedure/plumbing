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
RSpec.describe Plumbing::Operation do
  describe "events" do
    let(:doubler) do
      Class.new(Plumbing::Operation) do
        attribute :n, Integer
        attribute :result, _Nilable(Integer)
        starts_with :double
        action(:double) { self.result = n * 2 }.then :done
        result :done
      end
    end

    it "emits Started, Transitioned and Completed to the pipeline in order" do
      events = []
      pipeline = Plumbing::Pipeline::Source.new
      pipeline.observe { |event| events << event }
      doubler.call(pipeline: pipeline, n: 5)
      expect(events.map(&:class)).to eq [
        Plumbing::Operation::Started,
        Plumbing::Operation::Transitioned,
        Plumbing::Operation::Completed
      ]
      expect(events.last.attributes).to eq({n: 5, result: 10})
      expect(events.last.state).to eq :done
    end

    it "works with no pipeline (events go nowhere)" do
      expect { doubler.call(n: 1) }.not_to raise_error
    end
  end
end
