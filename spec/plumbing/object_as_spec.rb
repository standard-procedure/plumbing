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

  it "accepts a Plumbing interface constant" do
    observer = Object.new
    def observer.observe = nil
    def observer.remove = nil
    def observer.remove_all = nil
    expect(observer.as(Plumbing::Observable)).to be(observer)
  end
end
