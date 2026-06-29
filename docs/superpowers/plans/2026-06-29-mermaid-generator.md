# Mermaid → Ruby Scaffold Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a `Plumbing::Operations::Task` skeleton from a mermaid `flowchart TD` — the inverse of `to_mermaid` — with placeholders for the three things a diagram can't carry (attributes, guard logic, action bodies).

**Architecture:** A pure text-in/text-out module `Plumbing::Operations::Generator`. A line-based **parser** turns mermaid into a `Node`/`Edge` model (kind from shape, node id = state name, label = prose, edge label = `go_to` label); an **emitter** turns that model into Ruby source, mirroring `to_mermaid`'s conventions so it round-trips. No runtime dependency — it only knows the DSL it writes.

**Tech Stack:** Ruby 4.x (regex, no external gem), RSpec, StandardRB.

This is **Spec 4** of the operations work (design: `docs/superpowers/specs/2026-06-29-mermaid-generator-design.md`). The engine (Spec 1) is on `main`.

## Global Constraints

- `# frozen_string_literal: true` atop every Ruby file.
- StandardRB clean: `bundle exec standardrb --fix <files>` before every commit.
- Run tests with `bundle exec rspec <path>`; full suite before the final commit.
- The generator is **opt-in** and **runtime-independent**: `require "plumbing/operations/generator"` must load with no other requires. It is NOT added to `lib/plumbing/operations.rb`.
- Node id = state name; the quoted label = prose (→ a doc comment); edge label = the `go_to` label.
- Errors raise `Plumbing::Operations::Generator::Error` (a `StandardError` subclass).
- Work on the `mermaid-generator` branch (already checked out). Do not push to `main`.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## File Structure

```
lib/plumbing/operations/generator.rb        # NEW — Generator module: from_mermaid, parse, emit, Node/Edge/Error
spec/plumbing/operations/generator_spec.rb  # NEW — parser units, emitter units, round-trip
```

---

### Task 1: Parser (mermaid text → Node/Edge model)

**Files:**
- Create: `lib/plumbing/operations/generator.rb`
- Test: `spec/plumbing/operations/generator_spec.rb` (create)

**Interfaces:**
- Produces:
  - `Plumbing::Operations::Generator::Error < StandardError`
  - `Plumbing::Operations::Generator::Node = Struct.new(:id, :kind, :label)` — `kind` is `:action|:decision|:wait|:result`
  - `Plumbing::Operations::Generator::Edge = Struct.new(:from, :to, :label)` — `label` nil = unlabelled
  - `Plumbing::Operations::Generator.parse(text) -> [nodes, edges, start_target]` where `nodes` is a `Hash{String => Node}` in shape-line order, `edges` an `Array<Edge>`, `start_target` a `String` or `nil`

- [ ] **Step 1: Write the failing test**

Create `spec/plumbing/operations/generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "plumbing/operations"
require "plumbing/operations/generator"

RSpec.describe Plumbing::Operations::Generator do
  describe ".parse" do
    it "reads each shape into the right kind" do
      nodes, _edges, _start = described_class.parse(<<~MMD)
        flowchart TD
        act["do a thing"]
        dec{"is it ok?"}
        wt{{"await something"}}
        res(["finished"])
      MMD
      expect(nodes["act"].kind).to eq :action
      expect(nodes["act"].label).to eq "do a thing"
      expect(nodes["dec"].kind).to eq :decision
      expect(nodes["wt"].kind).to eq :wait
      expect(nodes["res"].kind).to eq :result
    end

    it "reads the start marker and its target, without making it a state" do
      nodes, _edges, start = described_class.parse("start([Start]) --> begin\nbegin(["done"])")
      expect(start).to eq "begin"
      expect(nodes).not_to have_key("start")
    end

    it "reads a combined node+edge line and a standalone edge" do
      nodes, edges, _start = described_class.parse(<<~MMD)
        a["one"] --> b
        b{"two?"}
        b -->|yes| c
        c(["end"])
      MMD
      expect(nodes.keys).to eq %w[a b c]
      expect(edges).to include(described_class::Edge.new("a", "b", nil))
      expect(edges).to include(described_class::Edge.new("b", "c", "yes"))
    end

    it "ignores blank lines, flowchart headers and %% comments" do
      nodes, _edges, _start = described_class.parse("flowchart TD\n\n%% mermaid-flow:pos x=1\nx(["only"])")
      expect(nodes.keys).to eq %w[x]
    end

    it "raises on an unparseable line" do
      expect { described_class.parse("this is not mermaid") }.to raise_error(Plumbing::Operations::Generator::Error, /line 1/)
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/generator_spec.rb`
Expected: FAIL — `cannot load such file -- plumbing/operations/generator`.

- [ ] **Step 3: Implement the parser**

Create `lib/plumbing/operations/generator.rb`:

```ruby
# frozen_string_literal: true

module Plumbing
  module Operations
    # Generates a Plumbing::Operations::Task skeleton from a mermaid flowchart —
    # the inverse of Task#to_mermaid. Pure text-in / text-out; no runtime deps.
    module Generator
      Error = Class.new(StandardError)

      Node = Struct.new(:id, :kind, :label) # kind: :action|:decision|:wait|:result
      Edge = Struct.new(:from, :to, :label) # label nil = unlabelled

      # A node (id + shape) optionally followed by an edge on the same line.
      NODE_AND_EDGE = /\A
        (?<node>\w+(?:\(\[.*?\]\)|\{\{".*?"\}\}|\{".*?"\}|\[".*?"\]))
        (?:\s*-->\s*(?:\|(?<elabel>[^|]*)\|\s*)?(?<target>\w+))?
      \z/x

      # A standalone edge: `from --> to` or `from -->|label| to`.
      EDGE_ONLY = /\A(?<from>\w+)\s*-->\s*(?:\|(?<elabel>[^|]*)\|\s*)?(?<target>\w+)\z/

      module_function

      def parse(text)
        nodes = {}
        edges = []
        start_target = nil
        text.each_line.with_index(1) do |raw, lineno|
          line = raw.strip
          next if line.empty? || line.start_with?("%%", "flowchart", "graph")

          if (m = NODE_AND_EDGE.match(line))
            node, kind = build_node(m[:node], lineno)
            if kind == :start
              start_target = m[:target] if m[:target]
            else
              nodes[node.id] = node
              edges << Edge.new(node.id, m[:target], blank_to_nil(m[:elabel])) if m[:target]
            end
          elsif (m = EDGE_ONLY.match(line))
            if m[:from] == "start"
              start_target = m[:target]
            else
              edges << Edge.new(m[:from], m[:target], blank_to_nil(m[:elabel]))
            end
          else
            raise Error, "line #{lineno}: cannot parse #{line.inspect}"
          end
        end
        [nodes, edges, start_target]
      end

      def build_node(token, lineno)
        case token
        when /\A(\w+)\(\[(.*)\]\)\z/
          id = $1
          label = unquote($2)
          (id == "start" || label.casecmp?("Start")) ? [Node.new(id, :start, label), :start] : [Node.new(id, :result, label), :result]
        when /\A(\w+)\{\{(.*)\}\}\z/
          [Node.new($1, :wait, unquote($2)), :wait]
        when /\A(\w+)\{(.*)\}\z/
          [Node.new($1, :decision, unquote($2)), :decision]
        when /\A(\w+)\[(.*)\]\z/
          [Node.new($1, :action, unquote($2)), :action]
        else
          raise Error, "line #{lineno}: unrecognised node #{token.inspect}"
        end
      end

      def unquote(str)
        s = str.strip
        (s.start_with?('"') && s.end_with?('"') && s.length >= 2) ? s[1..-2] : s
      end

      def blank_to_nil(str) = (str.nil? || str.empty?) ? nil : str
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/generator_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/generator.rb spec/plumbing/operations/generator_spec.rb
bundle exec rspec spec/plumbing/operations/generator_spec.rb
git add lib/plumbing/operations/generator.rb spec/plumbing/operations/generator_spec.rb
git commit -m "feat(operations): mermaid generator parser (text -> Node/Edge model)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Emitter, validation, and `from_mermaid`

**Files:**
- Modify: `lib/plumbing/operations/generator.rb` (add `from_mermaid`, `emit`, `resolve_start`, `validate!`, `emit_node`, `go_to`)
- Test: `spec/plumbing/operations/generator_spec.rb` (add)

**Interfaces:**
- Consumes: `parse` (Task 1), `Node`, `Edge`, `Error`.
- Produces:
  - `Plumbing::Operations::Generator.from_mermaid(mermaid, class_name:) -> String` of Ruby source (ends with a newline).
  - Validation raises `Error` for: an action with ≠1 outgoing edge; a decision/wait with 0 outgoing; a result with >0 outgoing; an edge to/from an undefined node; an unresolvable start.

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/generator_spec.rb`:

```ruby
  describe ".from_mermaid" do
    it "emits the class header, attributes placeholder and starts_with" do
      src = described_class.from_mermaid("start([Start]) --> done\ndone(["finished"])", class_name: "Simple")
      expect(src).to include("class Simple < Plumbing::Operations::Task")
      expect(src).to include("# TODO: declare attributes")
      expect(src).to include("starts_with :done")
      expect(src).to include("result :done")
    end

    it "emits a decision with guarded and else go_to branches, plus a comment" do
      src = described_class.from_mermaid(<<~MMD, class_name: "Decider")
        start([Start]) --> pick
        pick{"which way?"} -->|left| go_left
        pick --> go_right
        go_left(["L"])
        go_right(["R"])
      MMD
      expect(src).to include("# which way?")
      expect(src).to include("decision :pick do")
      expect(src).to include(%(go_to :go_left, "left", if: -> { raise NotImplementedError }))
      expect(src).to include("go_to :go_right\n")
    end

    it "emits an action with a single then and a wait_until block" do
      src = described_class.from_mermaid(<<~MMD, class_name: "Mix")
        start([Start]) --> work
        work["do work"] --> hold
        hold{{"wait for it"}} -->|ready| done
        done(["done"])
      MMD
      expect(src).to include("action(:work) { raise NotImplementedError }.then :hold")
      expect(src).to include("wait_until :hold do")
      expect(src).to include(%(go_to :done, "ready", if: -> { raise NotImplementedError }))
    end

    it "raises when an action has more than one outgoing edge" do
      expect {
        described_class.from_mermaid(<<~MMD, class_name: "Bad")
          start([Start]) --> a
          a["x"] --> b
          a --> c
          b(["b"])
          c(["c"])
        MMD
      }.to raise_error(Plumbing::Operations::Generator::Error, /action :a/)
    end

    it "raises when an edge targets an undefined node" do
      expect {
        described_class.from_mermaid("start([Start]) --> a\na["x"] --> ghost", class_name: "Bad")
      }.to raise_error(Plumbing::Operations::Generator::Error, /undefined node :ghost/)
    end

    it "infers the start from the node with no inbound edge when no Start marker is present" do
      src = described_class.from_mermaid("a["x"] --> b\nb(["b"])", class_name: "NoMarker")
      expect(src).to include("starts_with :a")
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/generator_spec.rb -e "from_mermaid"`
Expected: FAIL — `undefined method 'from_mermaid'`.

- [ ] **Step 3: Implement the emitter**

In `lib/plumbing/operations/generator.rb`, add these methods inside the `module Generator` `module_function` section (after `blank_to_nil`):

```ruby
      def from_mermaid(mermaid, class_name:)
        nodes, edges, start_target = parse(mermaid)
        validate!(nodes, edges)
        emit(nodes, edges, resolve_start(nodes, edges, start_target), class_name)
      end

      def validate!(nodes, edges)
        edges.each do |edge|
          raise Error, "edge references undefined node :#{edge.from}" unless nodes.key?(edge.from)
          raise Error, "edge references undefined node :#{edge.to}" unless nodes.key?(edge.to)
        end
        nodes.each_value do |node|
          outgoing = edges.count { |edge| edge.from == node.id }
          case node.kind
          when :action
            raise Error, "action :#{node.id} has #{outgoing} transitions — actions take exactly one (use a decision/wait shape)" unless outgoing == 1
          when :decision, :wait
            raise Error, "#{node.kind} :#{node.id} has no outgoing transitions" if outgoing.zero?
          when :result
            raise Error, "result :#{node.id} has outgoing transitions" unless outgoing.zero?
          end
        end
      end

      def resolve_start(nodes, edges, start_target)
        return start_target if start_target
        inbound = edges.map(&:to)
        candidates = nodes.keys.reject { |id| inbound.include?(id) }
        raise Error, "cannot determine the start state (no Start marker; #{candidates.size} nodes have no inbound edge)" unless candidates.size == 1
        candidates.first
      end

      def emit(nodes, edges, start, class_name)
        out = []
        out << "# Generated from a mermaid flowchart. Fill in the attributes, guard bodies and"
        out << "# action bodies (marked `raise NotImplementedError`), then run `standardrb --fix`."
        out << "class #{class_name} < Plumbing::Operations::Task"
        out << "  # TODO: declare attributes, e.g. attribute :name, String"
        out << ""
        out << "  starts_with :#{start}"
        nodes.each_value do |node|
          out << ""
          out.concat(emit_node(node, edges))
        end
        out << "end"
        out.join("\n") + "\n"
      end

      def emit_node(node, edges)
        outgoing = edges.select { |edge| edge.from == node.id }
        lines = []
        lines << "  # #{node.label}" if node.label && !node.label.empty? && node.label != node.id
        case node.kind
        when :action
          edge = outgoing.first
          lines << "  # (edge label #{edge.label.inspect} dropped — actions take no label)" if edge.label
          lines << "  action(:#{node.id}) { raise NotImplementedError }.then :#{edge.to}"
        when :decision
          lines << "  decision :#{node.id} do"
          outgoing.each { |edge| lines << "    #{go_to(edge)}" }
          lines << "  end"
        when :wait
          lines << "  wait_until :#{node.id} do"
          outgoing.each { |edge| lines << "    #{go_to(edge)}" }
          lines << "  end"
        when :result
          lines << "  result :#{node.id}"
        end
        lines
      end

      def go_to(edge)
        if edge.label
          "go_to :#{edge.to}, #{edge.label.inspect}, if: -> { raise NotImplementedError }"
        else
          "go_to :#{edge.to}"
        end
      end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/plumbing/operations/generator_spec.rb -e "from_mermaid"`
Expected: PASS (6 examples).

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix lib/plumbing/operations/generator.rb spec/plumbing/operations/generator_spec.rb
bundle exec rspec spec/plumbing/operations/generator_spec.rb
git add lib/plumbing/operations/generator.rb spec/plumbing/operations/generator_spec.rb
git commit -m "feat(operations): mermaid generator emitter + validation + from_mermaid

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Round-trip integration

**Files:**
- Test: `spec/plumbing/operations/generator_spec.rb` (add)

**Interfaces:**
- Consumes: `from_mermaid` (Task 2), `Plumbing::Operations::Task#to_mermaid` (Spec 1, on `main`).

- [ ] **Step 1: Write the failing test**

Add to `spec/plumbing/operations/generator_spec.rb`:

```ruby
  describe "round-trip" do
    it "generates Ruby that, once defined, renders an equivalent flowchart" do
      input = <<~MMD
        flowchart TD
          start([Start]) --> what_day
          what_day{"what day is it?"} -->|Saturday| buy_food
          what_day -->|Weekday| go_to_work
          buy_food["order the food"] --> party
          party(["party!"])
          go_to_work(["go to work"])
      MMD

      src = described_class.from_mermaid(input, class_name: "RoundTripParty")
      eval(src) # rubocop:disable Security/Eval — generated, trusted, test-only

      diagram = RoundTripParty.to_mermaid
      expect(diagram).to start_with("flowchart TD")
      expect(diagram).to include("start([Start]) --> what_day")
      expect(diagram).to include(%(what_day{"what_day"}))
      expect(diagram).to include("what_day -->|Saturday| buy_food")
      expect(diagram).to include("what_day -->|Weekday| go_to_work")
      expect(diagram).to include(%(buy_food["buy_food"] --> party))
      expect(diagram).to include(%(party(["party"])))
      expect(diagram).to include(%(go_to_work(["go_to_work"])))
    end
  end
```

> Why this works: `to_mermaid` reads only the structure (states + transitions + labels), never
> the `raise NotImplementedError` bodies, so the eval'd skeleton renders fine. The re-rendered
> diagram uses the state *names* as node labels (the round-trip drops the original prose labels,
> which is expected — prose lives in the source comments, not the structure). Edge labels
> (`Saturday`, `Weekday`) survive because they are `go_to` labels.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/plumbing/operations/generator_spec.rb -e "round-trip"`
Expected: FAIL — `uninitialized constant RoundTripParty` only if Task 2 incomplete; otherwise it should PASS immediately since `from_mermaid` and `to_mermaid` already exist. If it passes on first run, that is acceptable here: this is an integration test over two already-built units, not new production code. Confirm it genuinely exercises the path by temporarily breaking one `expect` and re-running.

- [ ] **Step 3: No new implementation**

This task adds only an integration test; `from_mermaid` (Task 2) and `to_mermaid` (Spec 1) already provide the behaviour. If the test fails, the failure points at a real defect in Task 2's emitter — fix it there, not by weakening the test.

- [ ] **Step 4: Run the full suite to verify it passes**

Run: `bundle exec rspec`
Expected: PASS — all pre-existing examples plus the generator examples.

- [ ] **Step 5: StandardRB and commit**

```bash
cd /Volumes/HD/Developer/Collabor8Online/plumbing
bundle exec standardrb --fix spec/plumbing/operations/generator_spec.rb
bundle exec rspec
git add spec/plumbing/operations/generator_spec.rb
git commit -m "test(operations): mermaid generator round-trip (mermaid -> ruby -> mermaid)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (vs `2026-06-29-mermaid-generator-design.md`):**
- `from_mermaid(mermaid, class_name:) -> String`, opt-in, runtime-independent → Tasks 1–2. ✓
- Line-based parse → Node/Edge model; kind from shape; id=name, label=comment, edge label=go_to label → Task 1. ✓
- Emit table (action/decision/wait/result), guarded-vs-else, `starts_with`, attributes placeholder, header → Task 2. ✓
- Start from marker or inbound-less node → Task 2 (`resolve_start`). ✓
- Validation (action arity, undefined target, decision/wait ≥1, result 0, missing start, unparseable line) → Tasks 1 (line) + 2 (structural). ✓
- Ignore blank/`flowchart`/`%%` lines → Task 1. ✓
- Start marker recognised by id `start`/label `Start`, not emitted as a state → Task 1 (`build_node`). ✓
- Action edge label dropped with a note → Task 2 (`emit_node`). ✓
- Three-layer testing incl. the eval round-trip → Tasks 1, 2, 3. ✓
- Out of scope (CLI, attribute/guard/body inference, full mermaid) → correctly absent. ✓

**2. Placeholder scan:** No TBD/TODO/"handle errors"/"similar to" in the plan. The only "TODO" strings are inside the generator's *output* (the attributes placeholder) — intentional. Every code step is complete; every command has expected output. Task 3's "may pass on first run" is explained, not a gap. ✓

**3. Type consistency:** `Node(:id,:kind,:label)`, `Edge(:from,:to,:label)`, `Error`, `parse -> [nodes(Hash), edges(Array), start_target]`, `from_mermaid(mermaid, class_name:) -> String`, and the helpers `build_node`/`unquote`/`blank_to_nil`/`validate!`/`resolve_start`/`emit`/`emit_node`/`go_to` are named identically across the Interfaces blocks and code. The emitter consumes exactly the `parse` return shape. ✓
