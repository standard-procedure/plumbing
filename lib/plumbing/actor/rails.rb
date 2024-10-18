require_relative "threaded"

module Plumbing
  module Actor
    class Rails < Threaded
      protected

      def in_actor_thread(&)
        super do
          Rails.application.executor.wrap(&)
        end
      end
    end
  end
end
