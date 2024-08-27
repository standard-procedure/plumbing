require "spec_helper"
require "async"
require_relative "../../lib/plumbing/valve/async"

RSpec.describe Plumbing::Valve do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Counter
    extend Plumbing::Valve
    query :name
    query :count
    command :slowly_increment

    def initialize name, initial_value: 0
      @name = name
      @count = initial_value
    end

    private

    attr_reader :name, :count

    def slowly_increment
      sleep 0.5
      @count += 1
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  it "knows which queries are defined" do
    expect(Counter.queries).to eq [:name, :count]
  end

  it "knows which commands are defined" do
    expect(Counter.commands).to eq [:slowly_increment]
  end

  it "reuses existing proxy classes" do
    @counter = Counter.start "inline counter", initial_value: 100
    @proxy_class = @counter.class

    @counter = Counter.start "another inline counter", initial_value: 200
    expect(@counter.class).to eq @proxy_class
  end

  context "inline" do
    it "sends all queries and commands immediately" do
      Plumbing.configure mode: :inline do
        @counter = Counter.start "inline counter", initial_value: 100

        expect(@counter.name).to eq "inline counter"
        expect(@counter.count).to eq 100

        @counter.slowly_increment
        expect(@counter.count).to eq 101
      end
    end
  end

  context "async" do
    it "sends all queries and commands using fibers" do
      Sync do
        Plumbing.configure mode: :async do
          @counter = Counter.start "async counter", initial_value: 100

          expect(@counter.name).to eq "async counter"
          expect(@counter.count).to eq 100

          @counter.slowly_increment
          # bypass the access protections to check the value before the async task has completed
          expect(@counter.send(:target).send(:count)).to eq 100
          expect(@counter.count).to become_equal_to { 101 }
        end
      end
    end
  end
end
