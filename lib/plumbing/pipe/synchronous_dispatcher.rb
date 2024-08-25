module Plumbing
  class Pipe
    class SynchronousDispatcher
      def dispatch event, observers:
        observers.collect do |observer|
          observer.call event
        rescue => ex
          puts ex
          ex
        end
      end
    end
  end
end
