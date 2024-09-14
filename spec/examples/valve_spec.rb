require "spec_helper"

RSpec.shared_examples "an example valve" do |runs_in_background|
  it "queries an object" do
    @person = Employee.start "Alice"

    expect(@person.name).to eq "Alice"
    expect(@person.job_title).to eq "Sales assistant"

    @time = Time.now
    # `greet_slowly` is a query so will block until a response is received
    expect(@person.greet_slowly).to eq "H E L L O"
    expect(Time.now - @time).to be > 0.1

    @time = Time.now
    # we're ignoring the result so this will not block (except :inline mode which does not run in the background)
    expect(@person.greet_slowly(ignore_result: true)).to be_nil
    expect(Time.now - @time).to be < 0.1 if runs_in_background
    expect(Time.now - @time).to be > 0.1 if !runs_in_background
  end

  it "commands an object" do
    @person = Employee.start "Alice"
    @person.promote
    @job_title = @person.job_title
    expect(@job_title).to eq "Sales manager"
  end
end

RSpec.describe "Valve example: " do
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

  context "inline mode" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it_behaves_like "an example valve", false
  end

  context "async mode" do
    around :example do |example|
      Plumbing.configure mode: :async do
        Kernel::Async(&example)
      end
    end

    it_behaves_like "an example valve", true
  end

  context "threaded mode" do
    around :example do |example|
      Plumbing.configure mode: :threaded, &example
    end

    it_behaves_like "an example valve", true
  end
end
