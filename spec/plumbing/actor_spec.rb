require "spec_helper"

require_relative "../../lib/plumbing/actor/async"
require_relative "../../lib/plumbing/actor/threaded"
require_relative "../../lib/plumbing/actor/rails"

RSpec.describe Plumbing::Actor do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Counter
    include Plumbing::Actor
    async :name, :count, :slow_query, "slowly_increment", "raises_error"
    attr_reader :name, :count

    def initialize name, initial_value: 0
      @name = name
      @count = initial_value
    end

    protected

    def slowly_increment
      sleep 0.2
      @count += 1
    end

    def slow_query
      sleep 0.2
      @count
    end

    def raises_error = raise "I'm an error"
  end

  class StepCounter < Counter
    async :step_value
    attr_reader :step_value

    def initialize name, initial_value: 0, step_value: 5
      super(name, initial_value: initial_value)
      @step_value = step_value
    end

    protected

    def slowly_increment
      sleep 0.2
      @count += @step_value
    end

    def failing_query
      raise "I'm a failure"
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  it "knows which async messages are understood" do
    expect(Counter.async_messages).to eq [:name, :count, :slow_query, :slowly_increment, :raises_error]
  end

  it "reuses existing proxy classes" do
    @counter = Counter.start "inline counter", initial_value: 100
    @proxy_class = @counter.class

    @counter = Counter.start "another inline counter", initial_value: 200
    expect(@counter.class).to eq @proxy_class
  end

  it "includes commands and queries from the superclass" do
    expect(StepCounter.async_messages).to eq [:name, :count, :slow_query, :slowly_increment, :raises_error, :step_value]

    @step_counter = StepCounter.start "step counter", initial_value: 100, step_value: 10

    expect(@step_counter.count.await).to eq 100
    expect(@step_counter.step_value.await).to eq 10
    @step_counter.slowly_increment
    expect(@step_counter.count.await).to eq 110
  end

  context "inline" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it "returns the result from a message immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      expect(@counter.name.await).to eq "inline counter"
      expect(@counter.count.await).to eq 100
      expect(Time.now - @time).to be < 0.1

      expect(@counter.slow_query.await).to eq 100
      expect(Time.now - @time).to be > 0.1
    end

    it "sends all commands immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      @counter.slowly_increment

      expect(@counter.count.await).to eq 101
      expect(Time.now - @time).to be > 0.1
    end
  end

  [:threaded, :async].each do |mode|
    context mode.to_s do
      around :example do |example|
        Sync do
          Plumbing.configure mode: mode, &example
        end
      end

      it "performs queries in the background and waits for the response" do
        @counter = Counter.start "async counter", initial_value: 100
        @time = Time.now

        expect(@counter.name.await).to eq "async counter"
        expect(@counter.count.await).to eq 100
        expect(Time.now - @time).to be < 0.1

        expect(@counter.slow_query.await).to eq 100
        expect(Time.now - @time).to be > 0.1
      end

      it "performs queries ignoring the response and returning immediately" do
        @counter = Counter.start "threaded counter", initial_value: 100
        @time = Time.now

        @counter.slow_query

        expect(Time.now - @time).to be < 0.1
      end

      it "performs commands in the background and returning immediately" do
        @counter = Counter.start "threaded counter", initial_value: 100
        @time = Time.now

        @counter.slowly_increment
        expect(Time.now - @time).to be < 0.1

        # wait for the background task to complete
        expect(101).to become_equal_to { @counter.count.await }
        expect(Time.now - @time).to be > 0.1
      end

      it "re-raises exceptions when checking the result" do
        @counter = Counter.start "failure"

        expect { @counter.raises_error.await }.to raise_error "I'm an error"
      end

      it "does not raise exceptions if ignoring the result" do
        @counter = Counter.start "failure"

        expect { @counter.raises_error }.not_to raise_error
      end
    end
  end

  context "threaded" do
    around :example do |example|
      Plumbing.configure mode: :threaded, &example
    end

    # standard:disable Lint/ConstantDefinitionInBlock
    class Record
      include GlobalID::Identification
      attr_reader :id
      def initialize id
        @id = id
      end

      def == other
        other.id == @id
      end
    end

    class Actor
      include Plumbing::Actor
      async :get_object_id, :get_object

      private def get_object_id(record) = record.object_id
      private def get_object(record) = record
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    it "packs and unpacks arguments when sending them across threads" do
      @actor = Actor.start
      @record = Record.new "999"

      @object_id = @actor.get_object_id(@record).await

      expect(@object_id).to_not eq @record.object_id
    end

    it "packs and unpacks results when sending them across threads" do
      @actor = Actor.start
      @record = Record.new "999"

      @object = @actor.get_object(@record).await

      expect(@object.id).to eq @record.id
      expect(@object.object_id).to_not eq @record.object_id
    end
  end
end
