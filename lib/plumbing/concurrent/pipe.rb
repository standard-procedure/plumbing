if RUBY_ENGINE != "opal"
  require_relative "../blocked_pipe"

  module Plumbing
    module Concurrent
      class Pipe < Plumbing::BlockedPipe
        def initialize
          super()
          @pipe = Ractor.new(self) do |instance|
            while (message = Ractor.receive) != :shutdown
              case message.first
              when :add_observer then instance.send :add_observing_ractor, message.last
              when :remove_observer then instance.send :remove_observing_ractor, message.last
              else instance.send :dispatch, message.last
              end
            end
          end
        end

        def add_observer ractor = nil, &block
          raise Plumbing::InvalidObserver.new("Only ractors permitted") unless (Ractor === ractor) && block.nil?
          @pipe << [:add_observer, ractor]
        end

        def << event
          raise Plumbing::InvalidEvent.new("Invalid event") unless Plumbing::Event === event
          @pipe << [:dispatch, event]
        end

        def shutdown
          @pipe << :shutdown
          super()
        end

        protected

        def dispatch event
          @observers.each do |observer|
            observer << event
          end
        end

        private

        def add_observing_ractor observer
          @observers << observer
        end

        def remove_observing_ractor observer
          @observers.delete observer
        end
      end
    end
  end
end
