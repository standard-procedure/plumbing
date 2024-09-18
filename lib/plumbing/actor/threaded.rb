require "concurrent/array"
require "concurrent/mvar"
require "concurrent/scheduled_task"
require "concurrent/immutable_struct"
require "concurrent/promises"
require_relative "transporter"

module Plumbing
  module Actor
    class Threaded
      attr_reader :target

      def initialize target
        @target = target
        @queue = Concurrent::Array.new
        @mutex = Thread::Mutex.new
      end

      # Send the message to the target and wrap the result
      def send_message(message_name, *args, **params, &block)
        puts "->#{@target.class}##{message_name}(#{args.inspect}, #{params.inspect})\n#{Thread.current.name}" if Plumbing.config.debug
        Message.new(@target, message_name, Plumbing::Actor.transporter.marshal(*args), Plumbing::Actor.transporter.marshal(params).first, block, Concurrent::MVar.new).tap do |message|
          @queue << message
          send_messages
        end
      end

      def safely(&)
        send_message(:perform_safely, &)
        nil
      end

      def in_context? = @mutex.owned?

      def stop = @queue.clear

      protected

      def in_actor_thread &block
        Concurrent::ScheduledTask.execute(0.1) do
          @mutex.synchronize(&block)
        end
      end

      private

      def send_messages
        in_context? ? dispatch_messages : in_actor_thread { dispatch_messages }
      end

      def dispatch_messages
        while (message = @queue.shift)
          message.call
        end
      end

      class Message < Concurrent::ImmutableStruct.new(:target, :message_name, :packed_args, :packed_params, :unsafe_block, :result)
        def call
          args = Plumbing::Actor.transporter.unmarshal(*packed_args)
          params = Plumbing::Actor.transporter.unmarshal(packed_params)
          puts "=> #{target.class}##{message_name}(#{args.first.inspect}, #{params.first.inspect}, &#{!unsafe_block.nil?})\n#{Thread.current.name}" if Plumbing.config.debug
          value = target.send message_name, *args, **params.first, &unsafe_block

          result.put Plumbing::Actor.transporter.marshal(value)
        rescue => ex
          puts ex
          puts ex.backtrace
          result.put ex
        end

        def value
          value = Plumbing::Actor.transporter.unmarshal(*result.take(Plumbing.config.timeout)).first
          raise value if value.is_a? Exception
          value
        end
      end
    end

    def self.transporter
      @transporter ||= Plumbing::Actor::Transporter.new
    end
  end
end
