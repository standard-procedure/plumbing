# frozen_string_literal: true

require "plumbing/operation"
require "plumbing/operation/generator"

RSpec.describe Plumbing::Operation::Generator do
  # describe ".parse" do
  #   it "reads each shape into the right kind" do
  #     nodes, _edges, _start = described_class.parse(<<~MMD)
  #       flowchart TD
  #       act["do a thing"]
  #       dec{"is it ok?"}
  #       wt{{"await something"}}
  #       res(["finished"])
  #     MMD
  #     expect(nodes["act"].kind).to eq :action
  #     expect(nodes["act"].label).to eq "do a thing"
  #     expect(nodes["dec"].kind).to eq :decision
  #     expect(nodes["wt"].kind).to eq :wait
  #     expect(nodes["res"].kind).to eq :result
  #   end

  #   it "reads the start marker and its target, without making it a state" do
  #     nodes, _edges, start = described_class.parse("start([Start]) --> begin\nbegin([\"done\"])")
  #     expect(start).to eq "begin"
  #     expect(nodes).not_to have_key("start")
  #   end

  #   it "reads a combined node+edge line and a standalone edge" do
  #     nodes, edges, _start = described_class.parse(<<~MMD)
  #       a["one"] --> b
  #       b{"two?"}
  #       b -->|yes| c
  #       c(["end"])
  #     MMD
  #     expect(nodes.keys).to eq %w[a b c]
  #     expect(edges).to include(described_class::Edge.new("a", "b", nil))
  #     expect(edges).to include(described_class::Edge.new("b", "c", "yes"))
  #   end

  #   it "ignores blank lines, flowchart headers and %% comments" do
  #     nodes, _edges, _start = described_class.parse("flowchart TD\n\n%% mermaid-flow:pos x=1\nx([\"only\"])")
  #     expect(nodes.keys).to eq %w[x]
  #   end

  #   it "raises on an unparseable line" do
  #     expect { described_class.parse("this is not mermaid") }.to raise_error(Plumbing::Operation::Generator::Error, /line 1/)
  #   end
  # end

  # describe ".from_mermaid" do
  #   it "emits the class header, attributes placeholder and starts_with" do
  #     src = described_class.from_mermaid("start([Start]) --> done\ndone([\"finished\"])", class_name: "Simple")
  #     expect(src).to include("class Simple < Plumbing::Operation")
  #     expect(src).to include("# TODO: declare attributes")
  #     expect(src).to include("starts_with :done")
  #     expect(src).to include("result :done")
  #   end

  #   it "emits a decision with guarded and else go_to branches, plus a comment" do
  #     src = described_class.from_mermaid(<<~MMD, class_name: "Decider")
  #       start([Start]) --> pick
  #       pick{"which way?"} -->|left| go_left
  #       pick --> go_right
  #       go_left(["L"])
  #       go_right(["R"])
  #     MMD
  #     expect(src).to include("# which way?")
  #     expect(src).to include("decision :pick do")
  #     expect(src).to include(%(go_to :go_left, "left", if: -> { raise NotImplementedError }))
  #     expect(src).to include("go_to :go_right\n")
  #   end

  #   it "emits an action with a single then and a wait_until block" do
  #     src = described_class.from_mermaid(<<~MMD, class_name: "Mix")
  #       start([Start]) --> work
  #       work["do work"] --> hold
  #       hold{{"wait for it"}} -->|ready| done
  #       done(["done"])
  #     MMD
  #     expect(src).to include("action(:work) { raise NotImplementedError }.then :hold")
  #     expect(src).to include("wait_until :hold do")
  #     expect(src).to include(%(go_to :done, "ready", if: -> { raise NotImplementedError }))
  #   end

  #   it "raises when an action has more than one outgoing edge" do
  #     expect {
  #       described_class.from_mermaid(<<~MMD, class_name: "Bad")
  #         start([Start]) --> a
  #         a["x"] --> b
  #         a --> c
  #         b(["b"])
  #         c(["c"])
  #       MMD
  #     }.to raise_error(Plumbing::Operation::Generator::Error, /action :a/)
  #   end

  #   it "raises when an edge targets an undefined node" do
  #     expect {
  #       described_class.from_mermaid("start([Start]) --> a\na[\"x\"] --> ghost", class_name: "Bad")
  #     }.to raise_error(Plumbing::Operation::Generator::Error, /undefined node :ghost/)
  #   end

  #   it "infers the start from the node with no inbound edge when no Start marker is present" do
  #     src = described_class.from_mermaid("a[\"x\"] --> b\nb([\"b\"])", class_name: "NoMarker")
  #     expect(src).to include("starts_with :a")
  #   end
  # end

  # describe "round-trip" do
  #   it "generates Ruby that, once defined, renders an equivalent flowchart" do
  #     input = <<~MMD
  #       flowchart TD
  #         start([Start]) --> what_day
  #         what_day{"what day is it?"} -->|Saturday| buy_food
  #         what_day -->|Weekday| go_to_work
  #         buy_food["order the food"] --> party
  #         party(["party!"])
  #         go_to_work(["go to work"])
  #     MMD

  #     src = described_class.from_mermaid(input, class_name: "RoundTripParty")
  #     eval(src) # rubocop:disable Security/Eval -- generated, trusted, test-only

  #     diagram = RoundTripParty.to_mermaid
  #     expect(diagram).to start_with("flowchart TD")
  #     expect(diagram).to include("start([Start]) --> what_day")
  #     expect(diagram).to include(%(what_day{"what_day"}))
  #     expect(diagram).to include("what_day -->|Saturday| buy_food")
  #     expect(diagram).to include("what_day -->|Weekday| go_to_work")
  #     expect(diagram).to include(%(buy_food["buy_food"] --> party))
  #     expect(diagram).to include(%(party(["party"])))
  #     expect(diagram).to include(%(go_to_work(["go_to_work"])))
  #   end
  # end
end
