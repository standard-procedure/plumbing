# frozen_string_literal: true

require_relative "../event"
require_relative "../pipeline"

module Plumbing
  class Operation
    # Lifecycle events. Each checkpoint carries the operation id, the current
    # state, and a full attributes snapshot — enough for a persistence observer
    # to upsert (operation_id, state, attributes).
    class Started < Plumbing::Event
    end

    class Transitioned < Plumbing::Event
      prop :from, Symbol
      prop :via, _Nilable(String)
    end

    class Completed < Plumbing::Event
    end

    class Failed < Plumbing::Event
    end

    class Waiting < Plumbing::Event
    end

    [Started, Transitioned, Waiting, Completed, Failed].each { |klass| Plumbing::Event.types.register(klass) }
  end
end
