require "spec_helper"
require "plumbing/event_dispatcher/fiber"
require "async"

RSpec.describe "Pipe examples" do
  it "observes events" do
    @source = Plumbing::Pipe.start

    @result = []
    @observer = @source.add_observer do |event|
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
    @observer = @filter.add_observer do |event|
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
        @events << event
        if @events.count >= 3
          @events.clear
          self << event
        end
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    @source = Plumbing::Pipe.start
    @filter = EveryThirdEvent.new(source: @source)

    @result = []
    @observer = @filter.add_observer do |event|
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
    @observer = @junction.add_observer do |event|
      @result << event.type
    end

    @first_source.notify "one"
    expect(@result).to eq ["one"]
    @second_source.notify "two"
    expect(@result).to eq ["one", "two"]
  end

  it "dispatches events asynchronously using fibers" do
    @first_source = Plumbing::Pipe.start dispatcher: Plumbing::EventDispatcher::Fiber.new
    @second_source = Plumbing::Pipe.start dispatcher: Plumbing::EventDispatcher::Fiber.new
    @junction = Plumbing::Junction.start @first_source, @second_source, dispatcher: Plumbing::EventDispatcher::Fiber.new
    @filter = Plumbing::Filter.start source: @junction, dispatcher: Plumbing::EventDispatcher::Fiber.new do |event|
      %w[one-one two-two].include? event.type
    end
    @result = []
    @filter.add_observer do |event|
      @result << event.type
    end

    Sync do
      @first_source.notify "one-one"
      @first_source.notify "one-two"
      @second_source.notify "two-one"
      @second_source.notify "two-two"

      expect(["one-one", "two-two"]).to become_equal_to { @result }
    end
  end
end
