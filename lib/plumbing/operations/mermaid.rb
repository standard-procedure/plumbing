# frozen_string_literal: true

module Plumbing
  module Operations
    # Renders a Task's states as a mermaid `flowchart TD`. Pure function of the
    # class's States — the structure is real; only edge labels are author text.
    module Mermaid
      SHAPES = {
        action: ->(name) { %(#{name}["#{name}"]) },
        decision: ->(name) { %(#{name}{"#{name}"}) },
        wait: ->(name) { %(#{name}{{"#{name}"}}) },
        result: ->(name) { %(#{name}(["#{name}"])) }
      }.freeze

      def to_mermaid
        lines = ["flowchart TD", "  start([Start]) --> #{start_state}"]
        states.each_value do |state|
          shape = SHAPES.fetch(state.kind).call(state.name)
          if state.transitions.length == 1 && state.transitions.first.label.nil?
            # Combine node shape and unconditional edge on one line
            lines << "  #{shape} --> #{state.transitions.first.target}"
          else
            lines << "  #{shape}"
            state.transitions.each do |transition|
              edge = transition.label.nil? ? "-->" : "-->|#{transition.label}|"
              lines << "  #{state.name} #{edge} #{transition.target}"
            end
          end
        end
        lines.join("\n")
      end
    end
  end
end
