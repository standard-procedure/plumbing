# Plumbing::RubberDuck - duck-types and type-casts

Define an [interface or protocol](https://en.wikipedia.org/wiki/Interface_(object-oriented_programming)) specifying which messages you expect to be able to send.

Then cast an object into that type.  This first tests that the object can respond to those messages and then builds a proxy that responds to those messages (and no others).  However, if you take one of these proxies, you can safely re-cast it as another type (as long as the original target object responds to the correct messages).

## Usage

Define your interface (Person in this example), then cast your objects (instances of PersonData and CarData).

[Casting objects as duck-types](/spec/examples/rubber_duck_spec.rb):
```ruby
  require "plumbing"

  Person = Plumbing::RubberDuck.define :first_name, :last_name, :email
  LikesFood = Plumbing::RubberDuck.define :favourite_food

  PersonData = Struct.new(:first_name, :last_name, :email, :favourite_food)
  CarData = Struct.new(:make, :model, :colour)

  @porsche_911 = CarData.new "Porsche", "911", "black"
  @person = @porsche_911.as Person
  # => Raises a TypeError as CarData does not respond_to #first_name, #last_name, #email

  @alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"
  @person = @alice.as Person
  @person.first_name
  # => "Alice"
  @person.email
  # => "alice@example.com"
  @person.favourite_food
  # => NoMethodError - #favourite_food is not part of the Person rubber duck (even though it is part of the underlying PersonData struct)

  # Cast our Person into a LikesFood rubber duck
  @hungry = @person.as LikesFood
  @hungry.favourite_food
  # => "Ice cream"
```

You can also use the same `@object.as type` pattern to type-check instances against modules or classes.  This creates a RubberDuck proxy based on the module or class you're casting into.  So the cast will pass if the object responds to the correct messages, even if a strict `.is_a?` test would fail.

```ruby
  require "plumbing"

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

  @porsche_911 = CarData.new "Porsche", "911", "black"
  expect { @porsche_911.as Person }.to raise_error(TypeError)

  @alice = PersonData.new "Alice", "Aardvark", "alice@example.com", "Ice cream"

  @alics.is_a? Person
  # => false - PersonData does not `include Person`
  @person = @alice.as Person
  # This cast is OK because PersonData responds to :first_name, :last_name and :email
  expect(@person.first_name).to eq "Alice"
  expect(@person.email).to eq "alice@example.com"
  expect { @person.favourite_food }.to raise_error(NoMethodError)

  @hungry = @person.as LikesFood
  expect(@hungry.favourite_food).to eq "Ice cream"
```
