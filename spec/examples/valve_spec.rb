require "spec_helper"

RSpec.describe "Valve examples" do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Employee
    include Plumbing::Valve
    query :name, :job_title
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
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  context "inline" do
    it "builds a valve" do
      Plumbing.configure mode: :inline do
        @person = Employee.start "Alice"

        expect(@person.name).to eq "Alice"
        expect(@person.job_title).to eq "Sales assistant"
        @person.promote

        expect(@person.job_title).to eq "Sales manager"
      end
    end
  end

  context "async" do
    it "builds a valve" do
      Plumbing.configure mode: :async do
        Sync do
          @person = Employee.start "Alice"

          expect(@person.name).to eq "Alice"
          expect(@person.job_title).to eq "Sales assistant"
          @person.promote

          expect("Sales manager").to become_equal_to { @person.job_title }
        end
      end
    end
  end
end
