# require "spec_helper"

# RSpec.describe "Valve examples" do
#   # standard:disable Lint/ConstantDefinitionInBlock
#   class Employee
#     extend Plumbing::Valve
#     query :name
#     query :job_title
#     command :promote

#     def initialize(name)
#       @name = name
#       @job_title = "Sales assistant"
#     end

#     attr_reader :name, :job_title

#     def promote
#       @job_title = "Sales manager"
#     end
#   end
#   # standard:enable Lint/ConstantDefinitionInBlock

#   context "inline" do
#     it "builds a valve" do
#       @person = Employee.start "Alice"

#       expect(@person.name).to eq "Alice"
#       expect(@person.job_title).to eq "Sales assistant"
#       @person.promote

#       expect("Sales manager").to become_equal_to { @person.job_title }
#     end
#   end

#   context "async" do
#     it "builds a valve" do
#       @person = Employee.start "Alice", mode: :async

#       expect(@person.name).to eq "Alice"
#       expect(@person.job_title).to eq "Sales assistant"
#       @person.promote

#       expect("Sales manager").to become_equal_to { @person.job_title }
#     end
#   end

#   context "threaded" do
#     it "builds a valve" do
#       @person = Employee.start "Alice", mode: :threaded

#       expect(@person.name).to eq "Alice"
#       expect(@person.job_title).to eq "Sales assistant"
#       @person.promote

#       expect("Sales manager").to become_equal_to { @person.job_title }
#     end
#   end

#   context "ractored" do
#     it "builds a valve" do
#       @person = Employee.start "Alice", mode: :ractor

#       expect(@person.name).to eq "Alice"
#       expect(@person.job_title).to eq "Sales assistant"
#       @person.promote

#       expect("Sales manager").to become_equal_to { @person.job_title }
#     end
#   end
# end
