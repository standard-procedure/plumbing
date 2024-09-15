module Plumbing
  module Valve
    ::Kernel.class_eval do
      def await &block
        block.call.value
      end
    end
  end
end
