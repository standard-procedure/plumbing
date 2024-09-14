require "spec_helper"

RSpec.describe "Rubber Duck examples" do
  it "casts objects into duck types" do
    # standard:disable Lint/ConstantDefinitionInBlock
    module DuckExample
      Person = Plumbing::RubberDuck.define :first_name, :last_name, :email
      LikesFood = Plumbing::RubberDuck.define :favourite_food

      PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
      CarData = Struct.new(:make, :model, :colour)
    end

    # standard:enable Lint/ConstantDefinitionInBlock

    @porsche_911 = DuckExample::CarData.new "Porsche", "911", "black"
    expect { @porsche_911.as DuckExample::Person }.to raise_error(TypeError)

    @alice = DuckExample::PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

    @person = @alice.as DuckExample::Person
    expect(@person.first_name).to eq "Alice"
    expect(@person.email).to eq "alice@example.com"
    expect { @person.favourite_food }.to raise_error(NoMethodError)

    @hungry = @person.as DuckExample::LikesFood
    expect(@hungry.favourite_food).to eq "Ice cream"
  end

  it "casts objects into modules" do
    # standard:disable Lint/ConstantDefinitionInBlock
    module ModuleExample
      module Person
        def first_name = @first_name

        def last_name = @last_name

        def email = @email
      end

      module LikesFood
        def favourite_food = @favourite_food
      end

      PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
      CarData = Struct.new(:make, :model, :colour)
    end
    # standard:enable Lint/ConstantDefinitionInBlock
    @porsche_911 = ModuleExample::CarData.new "Porsche", "911", "black"
    expect { @porsche_911.as ModuleExample::Person }.to raise_error(TypeError)

    @alice = ModuleExample::PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

    @person = @alice.as ModuleExample::Person
    expect(@person.first_name).to eq "Alice"
    expect(@person.email).to eq "alice@example.com"
    expect { @person.favourite_food }.to raise_error(NoMethodError)

    @hungry = @person.as ModuleExample::LikesFood
    expect(@hungry.favourite_food).to eq "Ice cream"
  end

  it "casts objects into clases" do
    # standard:disable Lint/ConstantDefinitionInBlock
    module ClassExample
      class Person
        def initialize first_name, last_name, email
          @first_name = first_name
          @last_name = last_name
          @email = email
        end

        attr_reader :first_name
        attr_reader :last_name
        attr_reader :email
      end

      class PersonWhoLikesFood < Person
        def initialize first_name, last_name, email, favourite_food
          super(first_name, last_name, email)
          @favourite_food = favourite_food
        end

        attr_reader :favourite_food
      end

      class CarData
        def initialize make, model, colour
          @make = make
          @model = model
          @colour = colour
        end
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock
    @porsche_911 = ClassExample::CarData.new "Porsche", "911", "black"
    expect { @porsche_911.as ClassExample::Person }.to raise_error(TypeError)

    @alice = ClassExample::PersonWhoLikesFood.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

    @person = @alice.as ClassExample::Person
    expect(@person.first_name).to eq "Alice"
    expect(@person.email).to eq "alice@example.com"
    expect { @person.favourite_food }.to raise_error(NoMethodError)

    @hungry = @person.as ClassExample::PersonWhoLikesFood
    expect(@hungry.favourite_food).to eq "Ice cream"
  end
end
