# frozen_string_literal: true

RSpec.describe Plumbing::Operation do
  # describe "#to_mermaid" do
  #   let(:task_class) do
  #     Class.new(Plumbing::Operation) do
  #       attribute :n, Integer
  #       starts_with :check
  #       decision :check do
  #         go_to :double, "positive", if: -> { n > 0 }
  #         go_to :zero, "non-positive"
  #       end
  #       action(:double) { self.n = n * 2 }.then :done
  #       result :done
  #       result :zero
  #     end
  #   end

  #   it "renders the flowchart with the right shapes and labelled edges" do
  #     diagram = task_class.to_mermaid
  #     expect(diagram).to start_with("flowchart TD")
  #     expect(diagram).to include("start([Start]) --> check")
  #     expect(diagram).to include(%(check{"check"}))
  #     expect(diagram).to include(%(check -->|positive| double))
  #     expect(diagram).to include(%(check -->|non-positive| zero))
  #     expect(diagram).to include(%(double["double"] --> done))
  #     expect(diagram).to include(%(done(["done"])))
  #   end
  # end
end
