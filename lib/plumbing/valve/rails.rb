require_relative "threaded"

module Plumbing
  module Valve
    class Rails < Threaded
      protected

      def future(&)
        Concurrent::Promises.future do
          Rails.application.executor.wrap(&)
        end
      end
    end
  end
end
