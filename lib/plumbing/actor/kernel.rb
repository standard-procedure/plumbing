require "timeout"

module Plumbing
  module Actor
    ::Kernel.class_eval do
      def await &block
        result = block.call
        result.respond_to?(:value) ? result.send(:value) : result
      end

      def wait_for timeout = nil, &block
        Timeout.timeout(timeout || Plumbing.config.timeout) do
          loop do
            break if block.call
            sleep 0.1
          end
        end
      end
    end
  end
end
