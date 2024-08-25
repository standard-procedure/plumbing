require "async/task"
require "async/semaphore"

module Plumbing
  class Pipe
    class FiberDispatcher
      def initialize limit: 4
        @semaphore = Async::Semaphore.new(limit)
      end

      def dispatch event, observers:
        @semaphore.async do |task|
          observers.collect do |observer|
            task.async do
              observer.call event
            rescue => ex
              puts ex
              ex
            end
          end
        end
      end
    end
  end
end
