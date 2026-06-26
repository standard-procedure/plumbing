# frozen_string_literal: true

class Object
  # Validate that this object satisfies the given literal interface/type and
  # return self. No narrowing proxy — validate-and-passthrough (the v1
  # replacement for the old RubberDuck cast).
  def as(interface)
    Literal.check(self, interface) # check(value, type) — raises Literal::TypeError on mismatch
    self
  end
end
