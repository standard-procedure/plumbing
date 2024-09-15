module Plumbing
  module Actor
    ::Kernel.class_eval do
      def await &block
        block.call.await
      end
    end
  end
end
