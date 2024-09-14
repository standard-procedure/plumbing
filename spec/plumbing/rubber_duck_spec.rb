require "spec_helper"

RSpec.describe Plumbing::RubberDuck do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Duck
    def quack = "Quack"

    def swim(place) = "Swim in #{place}"

    def fly(&block) = "Fly #{block.call}"
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  context "defining rubber ducks" do
    it "verifies that an object matches the RubberDuck type" do
      @duck_type = described_class.define :quack, :swim, :fly
      @duck = Duck.new

      expect(@duck_type.verify(@duck)).to eq @duck
    end

    it "casts the object to a duck type" do
      @duck_type = described_class.define :quack, :swim, :fly
      @duck = Duck.new

      @proxy = @duck.as @duck_type

      expect(@proxy).to be_kind_of Plumbing::RubberDuck::Proxy
      expect(@proxy).to respond_to :quack
      expect(@proxy.quack).to eq "Quack"
      expect(@proxy).to respond_to :swim
      expect(@proxy.swim("the river")).to eq "Swim in the river"
      expect(@proxy).to respond_to :fly
      expect(@proxy.fly { "ducky fly" }).to eq "Fly ducky fly"
    end

    it "does not forward methods that are not part of the duck type" do
      @duck_type = described_class.define :swim, :fly
      @duck = Duck.new

      @proxy = @duck.as @duck_type

      expect(@proxy).to_not respond_to :quack
    end

    it "does not wrap rubber ducks in a proxy" do
      @duck_type = described_class.define :swim, :fly
      @duck = Duck.new

      @proxy = @duck.as @duck_type

      expect(@proxy.as(@duck_type)).to eq @proxy
    end

    it "allows rubber ducks to be expanded and cast to other types" do
      @quackers = described_class.define :quack
      @swimming_bird = described_class.define :swim, :fly
      @duck = Duck.new

      @swimmer = @duck.as @swimming_bird
      @quacker = @swimmer.as @quackers

      expect(@swimmer).to respond_to :swim
      expect(@quacker).to respond_to :quack
    end

    it "raises a TypeError if the object does not respond to the given methods" do
      @cow_type = described_class.define :moo, :chew
      @duck = Duck.new

      expect { @cow_type.verify(@duck) }.to raise_error(TypeError)
    end
  end
end
