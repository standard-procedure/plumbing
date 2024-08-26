require "spec_helper"

RSpec.describe "Rubber Duck examples" do
  it "casts objects as duck types" do
    # standard:disable Lint/ConstantDefinitionInBlock
    Person = Plumbing::RubberDuck.define :first_name, :last_name, :email
    LikesFood = Plumbing::RubberDuck.define :favourite_food

    PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
    CarData = Struct.new(:make, :model, :colour)
    # standard:enable Lint/ConstantDefinitionInBlock

    @porsche_911 = CarData.new "Porsche", "911", "black"
    expect { @porsche_911.as Person }.to raise_error(TypeError)

    @alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

    @person = @alice.as Person
    expect(@person.first_name).to eq "Alice"
    expect(@person.email).to eq "alice@example.com"
    expect { @person.favourite_food }.to raise_error(NoMethodError)

    @hungry = @person.as LikesFood
    expect(@hungry.favourite_food).to eq "Ice cream"
  end
end
