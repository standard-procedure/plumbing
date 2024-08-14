require "async/task"
require "async/semaphore"

module Plumbing
  module Fiber
    # An implementation of a pipe that uses Fibers
    class Pipe < Plumbing::Pipe
      attr_reader :active

      def initialize limit: 4
        super()
        @limit = 4
        @semaphore = Async::Semaphore.new(@limit)
      end

      def << event
        raise Plumbing::InvalidEvent.new "event is not a Plumbing::Event" unless event.is_a? Plumbing::Event
        @semaphore.async do |task|
          dispatch event, task
        end
      end

      protected

      def dispatch event, task
        @observers.collect do |observer|
          task.async do
            observer.call event
          rescue => ex
            puts "Error: #{ex}"
          end
        end
      end
    end
  end
end
