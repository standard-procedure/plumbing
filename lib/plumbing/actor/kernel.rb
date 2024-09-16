module Plumbing
  module Actor
    ::Kernel.class_eval do
      def await &block
        result = block.call
        result.respond_to?(:value) ? result.send(:value) : result
      end
    end
  end
end
