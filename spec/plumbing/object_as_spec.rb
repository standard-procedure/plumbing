# frozen_string_literal: true

RSpec.describe "Object#as" do
  let(:callable) { Literal::Types._Callable }  # built into literal — don't redefine

  it "returns the object itself when it satisfies the interface" do
    duck = ->(x) { x }
    expect(duck.as(callable)).to be(duck)
  end

  it "raises when the object does not satisfy the interface" do
    expect { "not callable".as(callable) }.to raise_error(Literal::TypeError)
  end

  it "accepts an interface built with Literal::Types._Interface" do
    quacker = Literal::Types._Interface(:quack)
    duck = Object.new
    def duck.quack = "quack"
    expect(duck.as(quacker)).to be(duck)
  end
end
