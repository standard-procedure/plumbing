# frozen_string_literal: true

require_relative "../event"
require_relative "../pipeline"

module Plumbing
  module Operations
    # Lifecycle events. Each checkpoint carries the operation id, the current
    # state, and a full attributes snapshot — enough for a persistence observer
    # to upsert (operation_id, state, attributes).
    class Started < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :attributes, Hash
    end

    class Transitioned < Plumbing::Event
      prop :operation_id, Integer
      prop :from, Symbol
      prop :to, Symbol
      prop :via, _Nilable(String)
      prop :attributes, Hash
    end

    class Completed < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :attributes, Hash
    end

    class Failed < Plumbing::Event
      prop :operation_id, Integer
      prop :state, Symbol
      prop :exception, Exception
      prop :attributes, Hash
    end

    [Started, Transitioned, Completed, Failed].each { |klass| Plumbing::Pipeline.register(klass) }
  end
end
