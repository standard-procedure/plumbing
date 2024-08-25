require "spec_helper"

RSpec.describe Plumbing::RubberDuck do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Duck
    def quack = "Quack"

    def swim place
      "Swim in #{place}"
    end

    def fly &block
      "Fly #{block.call}"
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

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

  it "raises a TypeError if the class responds to the given methods" do
    cow_type = described_class.define :moo, :chew
    duck = Duck.new

    expect { cow_type.verify(duck) }.to raise_error(TypeError)
  end
end
