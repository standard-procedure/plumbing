# frozen_string_literal: true

# Shared event types for the pipeline specs.
class ThingHappened < Plumbing::Event
  prop :id, String
end

class ErrorRaised < Plumbing::Event
  prop :id, String
end

class InfoLogged < Plumbing::Event
  prop :id, String
end
