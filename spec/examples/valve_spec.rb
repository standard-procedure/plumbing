require "spec_helper"

RSpec.describe "Valve examples" do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Employee
    include Plumbing::Valve
    query :name, :job_title, :greet_slowly
    command :promote

    def initialize(name)
      @name = name
      @job_title = "Sales assistant"
    end

    attr_reader :name, :job_title

    def promote
      sleep 0.5
      @job_title = "Sales manager"
    end

    def greet_slowly
      sleep 0.2
      "H E L L O"
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  context "inline" do
    it "queries an object" do
      Plumbing.configure mode: :inline do
        @person = Employee.start "Alice"

        expect(@person.name).to eq "Alice"
        expect(@person.job_title).to eq "Sales assistant"

        @time = Time.now
        expect(@person.greet_slowly).to eq "H E L L O"
        expect(Time.now - @time).to be > 0.1

        @time = Time.now
        expect(@person.greet_slowly(ignore_result: true)).to be_nil
        expect(Time.now - @time).to be > 0.1
      end
    end

    it "commands an object" do
      Plumbing.configure mode: :inline do
        @person = Employee.start "Alice"

        @person.promote

        expect(@person.job_title).to eq "Sales manager"
      end
    end
  end

  context "async" do
    around :example do |example|
      Plumbing.configure mode: :async do
        Kernel::Async(&example)
      end
    end

    it "queries an object" do
      @person = Employee.start "Alice"

      expect(@person.name).to eq "Alice"
      expect(@person.job_title).to eq "Sales assistant"

      @time = Time.now
      expect(@person.greet_slowly).to eq "H E L L O"
      expect(Time.now - @time).to be > 0.1

      @time = Time.now
      expect(@person.greet_slowly(ignore_result: true)).to be_nil
      expect(Time.now - @time).to be < 0.1
    end

    it "commands an object" do
      @person = Employee.start "Alice"

      @person.promote

      expect(@person.job_title).to eq "Sales manager"
    end
  end
end
