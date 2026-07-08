# frozen_string_literal: true

# ErrorRaised / InfoLogged / ThingHappened are defined in spec/support/events.rb

RSpec.describe "Plumbing::Pipeline composition" do
  before { Plumbing::Actor.uses :inline }

  def collect(pipeline)
    names = []
    pipeline.observe { |event| names << event.class.name }
    names
  end

  describe Plumbing::Pipeline::Only do
    it "emits only matching event types (with wildcards)" do
      src = Plumbing::Pipeline::Source.new
      only = described_class.new(source: src, filters: ["Error*"])
      names = collect(only)
      await { src.push(event: ErrorRaised.new(id: "1")) }
      await { src.push(event: InfoLogged.new(id: "2")) }
      expect(names).to eq(["ErrorRaised"])
    end

    it "matches an exact (non-wildcard) name" do
      src = Plumbing::Pipeline::Source.new
      only = described_class.new(source: src, filters: ["InfoLogged"])
      names = collect(only)
      await { src.push(event: ErrorRaised.new(id: "1")) }
      await { src.push(event: InfoLogged.new(id: "2")) }
      expect(names).to eq(["InfoLogged"])
    end
  end

  describe Plumbing::Pipeline::Except do
    it "emits everything except the matches" do
      src = Plumbing::Pipeline::Source.new
      except = described_class.new(source: src, filters: ["Error*"])
      names = collect(except)
      await { src.push(event: ErrorRaised.new(id: "1")) }
      await { src.push(event: InfoLogged.new(id: "2")) }
      expect(names).to eq(["InfoLogged"])
    end
  end

  describe Plumbing::Pipeline::Filter do
    it "emits only Regexp-matching event types" do
      src = Plumbing::Pipeline::Source.new
      filter = described_class.new(source: src, filters: [/Error/])
      names = collect(filter)
      await { src.push(event: ErrorRaised.new(id: "1")) }
      await { src.push(event: InfoLogged.new(id: "2")) }
      expect(names).to eq(["ErrorRaised"])
    end
  end

  describe Plumbing::Pipeline::Junction do
    it "merges several sources into one" do
      a = Plumbing::Pipeline::Source.new
      b = Plumbing::Pipeline::Source.new
      junction = described_class.new(a, b)
      names = collect(junction)
      await { a.push(event: ErrorRaised.new(id: "1")) }
      await { b.push(event: InfoLogged.new(id: "2")) }
      expect(names.sort).to eq(["ErrorRaised", "InfoLogged"])
    end

    it "adds additional sources" do
      a = Plumbing::Pipeline::Source.new
      b = Plumbing::Pipeline::Source.new
      junction = described_class.new(a)
      names = collect(junction)
      await { a.push(event: ErrorRaised.new(id: "1")) }
      await { b.push(event: InfoLogged.new(id: "2")) }

      junction.add source: b
      await { a.push(event: ErrorRaised.new(id: "1")) }
      await { b.push(event: InfoLogged.new(id: "2")) }
      expect(names.sort).to eq(["ErrorRaised", "ErrorRaised", "InfoLogged"])
    end
  end

  it "composes: Only over a Junction of two sources" do
    a = Plumbing::Pipeline::Source.new
    b = Plumbing::Pipeline::Source.new
    junction = Plumbing::Pipeline::Junction.new(a, b)
    only = Plumbing::Pipeline::Only.new(source: junction, filters: ["Error*"])
    names = collect(only)
    await { a.push(event: ErrorRaised.new(id: "1")) }
    await { b.push(event: InfoLogged.new(id: "2")) }
    await { b.push(event: ErrorRaised.new(id: "3")) }
    expect(names).to eq(["ErrorRaised", "ErrorRaised"])
  end
end
