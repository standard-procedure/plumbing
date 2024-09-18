require "spec_helper"
require "plumbing/actor/async"
require "plumbing/actor/threaded"

RSpec.shared_examples "an example actor" do |runs_in_background|
  # standard:disable Lint/ConstantDefinitionInBlock
  class Employee
    include Plumbing::Actor
    async :name, :job_title, :greet_slowly, :promote

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
      sleep 0.5
      "H E L L O"
    end
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  it "queries an object" do
    @person = Employee.start "Alice"

    expect(await { @person.name }).to eq "Alice"
    expect(await { @person.job_title }).to eq "Sales assistant"

    @time = Time.now
    # `greet_slowly` is a query so will block until a response is received
    expect(await { @person.greet_slowly }).to eq "H E L L O"
    expect(Time.now - @time).to be > 0.1

    @time = Time.now
    # we're not awaiting the result, so this should run in the background (unless we're using inline mode)
    @person.greet_slowly

    expect(Time.now - @time).to be < 0.2 if runs_in_background
    expect(Time.now - @time).to be > 0.2 if !runs_in_background
  ensure
    @person.stop
  end

  it "commands an object" do
    @person = Employee.start "Alice"
    await { @person.promote }
    expect(@person.job_title.value).to eq "Sales manager"
  ensure
    @person.stop
  end
end

RSpec.describe "Actor example: " do
  context "inline mode" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it_behaves_like "an example actor", false
  end

  context "async mode" do
    around :example do |example|
      Plumbing.configure mode: :async do
        Kernel::Async(&example)
      end
    end

    it_behaves_like "an example actor", true
  end

  context "threaded mode" do
    around :example do |example|
      Plumbing.configure mode: :threaded, &example
    end

    it_behaves_like "an example actor", true
  end
end
