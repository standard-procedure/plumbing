require_relative "threaded"

module Plumbing
  module Actor
    class Rails < Threaded
      protected

      def in_context(&)
        super do
          Rails.application.executor.wrap(&)
        end
      end
    end
  end
end
