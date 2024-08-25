module Plumbing
  Callable = RubberDuck.define :call
  Observable = RubberDuck.define :add_observer, :remove_observer, :is_observer?
  DispatchesEvents = RubberDuck.define :add_observer, :remove_observer, :is_observer?, :shutdown, :dispatch
  Collection = RubberDuck.define :each, :<<, :delete, :include?
end
