require "spec_helper"

require_relative "../../lib/plumbing/valve/async"
require_relative "../../lib/plumbing/valve/threaded"

RSpec.describe Plumbing::Valve do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Counter
    include Plumbing::Valve
    query :name, :count, :am_i_failing?, :slow_query
    command "slowly_increment", "raises_error"
    attr_reader :name, :count

    def initialize name, initial_value: 0
      @name = name
      @count = initial_value
    end

    def slowly_increment
      sleep 0.5
      @count += 1
    end

    def slow_query
      sleep 0.5
      @count
    end

    def am_i_failing? = raise "I'm a failure"

    def raises_error = raise "I'm an error"
  end

  class StepCounter < Counter
    query :step_value
    attr_reader :step_value

    def initialize name, initial_value: 0, step_value: 5
      super(name, initial_value: initial_value)
      @step_value = step_value
    end

    def slowly_increment
      sleep 0.5
      @count += @step_value
    end

    def failing_query
      raise "I'm a failure"
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  it "knows which queries are defined" do
    expect(Counter.queries).to eq [:name, :count, :am_i_failing?, :slow_query]
  end

  it "knows which commands are defined" do
    expect(Counter.commands).to eq [:slowly_increment, :raises_error]
  end

  it "raises exceptions from queries" do
    @counter = Counter.start "failure"

    expect { @counter.am_i_failing? }.to raise_error "I'm a failure"
  end

  it "does not raise exceptions from commands" do
    @counter = Counter.start "failure"

    expect { @counter.raises_error }.not_to raise_error
  end

  it "raises exceptions from queries" do
    @counter = Counter.start "failure"

    expect { @counter.am_i_failing? }.to raise_error "I'm a failure"
  end

  it "reuses existing proxy classes" do
    @counter = Counter.start "inline counter", initial_value: 100
    @proxy_class = @counter.class

    @counter = Counter.start "another inline counter", initial_value: 200
    expect(@counter.class).to eq @proxy_class
  end

  it "includes commands and queries from the superclass" do
    expect(StepCounter.queries).to eq [:name, :count, :am_i_failing?, :slow_query, :step_value]
    expect(StepCounter.commands).to eq [:slowly_increment, :raises_error]

    @step_counter = StepCounter.start "step counter", initial_value: 100, step_value: 10

    expect(@step_counter.count).to eq 100
    expect(@step_counter.step_value).to eq 10
    @step_counter.slowly_increment
    expect(@step_counter.count).to eq 110
  end

  context "inline" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it "sends all queries immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      expect(@counter.name).to eq "inline counter"
      expect(@counter.count).to eq 100
      expect(Time.now - @time).to be < 0.1

      expect(@counter.slow_query).to eq 100
      expect(Time.now - @time).to be > 0.4
    end

    it "sends all commands immediately" do
      @counter = Counter.start "inline counter", initial_value: 100
      @time = Time.now

      @counter.slowly_increment

      expect(@counter.count).to eq 101
      expect(Time.now - @time).to be > 0.4
    end
  end

  context "async" do
    around :example do |example|
      Sync do
        Plumbing.configure mode: :async, &example
      end
    end

    it "sends all queries using fibers and waits for the response" do
      @counter = Counter.start "async counter", initial_value: 100
      @time = Time.now

      expect(@counter.name).to eq "async counter"
      expect(@counter.count).to eq 100
      expect(Time.now - @time).to be < 0.1

      expect(@counter.slow_query).to eq 100
      expect(Time.now - @time).to be > 0.4
    end

    it "ignores the response from a query and returns immediately" do
      @counter = Counter.start "async counter", initial_value: 100
      @time = Time.now

      expect(@counter.slow_query(ignore_result: true)).to be_nil

      expect(Time.now - @time).to be < 0.1
    end

    it "sends all commands using fibers without waiting for the response" do
      @counter = Counter.start "async counter", initial_value: 100
      @time = Time.now

      @counter.slowly_increment
      expect(Time.now - @time).to be < 0.1

      # wait for the async task to complete
      expect(101).to become_equal_to { @counter.count }
      expect(Time.now - @time).to be > 0.4
    end
  end

  context "threaded" do
    around :example do |example|
      Sync do
        Plumbing.configure mode: :threaded, &example
      end
    end

    it "sends all queries using threads and waits for the response" do
      @counter = Counter.start "async counter", initial_value: 100
      @time = Time.now

      expect(@counter.name).to eq "async counter"
      expect(@counter.count).to eq 100
      expect(Time.now - @time).to be < 0.1

      expect(@counter.slow_query).to eq 100
      expect(Time.now - @time).to be > 0.4
    end

    it "ignores the response from a query and returns immediately" do
      @counter = Counter.start "threaded counter", initial_value: 100
      @time = Time.now

      expect(@counter.slow_query(ignore_result: true)).to be_nil

      expect(Time.now - @time).to be < 0.1
    end

    it "sends all commands using threads without waiting for the response" do
      @counter = Counter.start "threaded counter", initial_value: 100
      @time = Time.now

      @counter.slowly_increment
      expect(Time.now - @time).to be < 0.1

      # wait for the threaded task to complete
      expect(101).to become_equal_to { @counter.count }
      expect(Time.now - @time).to be > 0.4
    end
  end
end
