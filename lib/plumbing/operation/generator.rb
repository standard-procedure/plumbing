# frozen_string_literal: true

module Plumbing
  class Operation
    # Generates a Plumbing::Operation skeleton from a mermaid flowchart —
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
        out << "class #{class_name} < Plumbing::Operation"
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
    end
  end
end
