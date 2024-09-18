require "spec_helper"
require "async"
require "plumbing/actor/async"
require "plumbing/actor/threaded"

RSpec.describe "Pipe examples" do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it "observes events" do
        @source = Plumbing::Pipe.start

        @result = []
        @source.add_observer do |event|
          @result << event.type
        end

        @source.notify "something_happened", message: "But what was it?"
        expect(@result).to eq ["something_happened"]
      end

      it "filters events" do
        @source = Plumbing::Pipe.start

        @filter = Plumbing::Filter.start source: @source do |event|
          %w[important urgent].include? event.type
        end

        @result = []
        @filter.add_observer do |event|
          @result << event.type
        end

        @source.notify "important", message: "ALERT! ALERT!"
        expect(@result).to eq ["important"]

        @source.notify "unimportant", message: "Nothing to see here"
        expect(@result).to eq ["important"]
      end

      it "allows for custom filters" do
        # standard:disable Lint/ConstantDefinitionInBlock
        class EveryThirdEvent < Plumbing::CustomFilter
          def initialize source:
            super
            @events = []
          end

          def received event
            safely do
              @events << event
              if @events.count >= 3
                @events.clear
                self << event
              end
            end
          end
        end
        # standard:enable Lint/ConstantDefinitionInBlock

        @source = Plumbing::Pipe.start
        @filter = EveryThirdEvent.start(source: @source)

        @result = []
        @filter.add_observer do |event|
          @result << event.type
        end

        1.upto 10 do |i|
          @source.notify i.to_s
        end

        expect(@result).to eq ["3", "6", "9"]
      end

      it "joins multiple source pipes" do
        @first_source = Plumbing::Pipe.start
        @second_source = Plumbing::Pipe.start

        @junction = Plumbing::Junction.start @first_source, @second_source

        @result = []
        @junction.add_observer do |event|
          @result << event.type
        end

        @first_source.notify "one"
        expect(@result).to eq ["one"]
        @second_source.notify "two"
        expect(@result).to eq ["one", "two"]
      end

      it "dispatches events asynchronously using async" do
        Plumbing.configure mode: :async do
          Sync do
            @first_source = Plumbing::Pipe.start
            @second_source = Plumbing::Pipe.start
            @junction = Plumbing::Junction.start @first_source, @second_source
            @filter = Plumbing::Filter.start source: @junction do |event|
              %w[one-one two-two].include? event.type
            end
            @result = []
            @filter.add_observer do |event|
              @result << event.type
            end

            @first_source.notify "one-one"
            @first_source.notify "one-two"
            @second_source.notify "two-one"
            @second_source.notify "two-two"

            expect { @result.sort }.to become(["one-one", "two-two"])
          end
        end
      end

      it "dispatches events asynchronously using threads" do
        Plumbing.configure mode: :threaded do
          @result = []

          @first_source = Plumbing::Pipe.start
          @second_source = Plumbing::Pipe.start
          @junction = Plumbing::Junction.start @first_source, @second_source

          @filter = Plumbing::Filter.start source: @junction do |event|
            %w[one-one two-two].include? event.type
          end
          await do
            @filter.add_observer do |event|
              @result << event.type
            end
          end

          @first_source.notify "one-one"
          @first_source.notify "one-two"
          @second_source.notify "two-one"
          @second_source.notify "two-two"

          expect { @result.sort }.to become(["one-one", "two-two"])
        ensure
          @first_source.shutdown
          @second_source.shutdown
          @junction.shutdown
          @filter.shutdown
        end
      end
    end
  end
end
