require "async/task"
require "async/semaphore"

module Plumbing
  class EventDispatcher
    class Fiber < EventDispatcher
      def initialize limit: 4
        super()
        @semaphore = Async::Semaphore.new(limit)
        @queue = Set.new
        @paused = false
      end

      def dispatch event
        @queue << event
        dispatch_events unless @paused
      end

      def pause
        @paused = true
      end

      def resume
        @paused = false
        dispatch_events
      end

      def queue_size
        @queue.size
      end

      def shutdown
        super
        @queue.clear
      end

      private

      def dispatch_events
        @semaphore.async do |task|
          events = @queue.dup
          @queue.clear
          events.each do |event|
            dispatch_event event, task
          end
        end
      end

      def dispatch_event event, task
        @observers.each do |observer|
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
