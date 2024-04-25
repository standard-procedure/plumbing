# if RUBY_ENGINE != "opal"
#   require "spec_helper"
#
#   require "plumbing/concurrent/pipe"
#   require "plumbing/concurrent/filter"
#
#   RSpec.describe Plumbing::Concurrent::Filter do
#     it "accepts event types" do
#       @pipe = Plumbing::Concurrent::Pipe.start
#
#       @filter = Plumbing::Concurrent::Filter.start(source: @pipe, accepts: %w[first_type third_type])
#
#       @observer = Ractor.new do
#         Ractor.yield Ractor.receive
#       end
#       @filter.add_observer @filter
#
#       @pipe.notify "first_type"
#       @pipe.notify "second_type"
#       @pipe.notify "third_type"
#
#       puts "1"
#       expect(@observer.take.type).to eq "first_type"
#       puts "1"
#       # second_type is omitted
#       puts "1"
#       expect(@observer.take.type).to eq "third_type"
#     end
#
#     it "rejects event types" do
#       @pipe = Plumbing::Concurrent::Pipe.start
#
#       @filter = Plumbing::Concurrent::Filter.start(source: @pipe, rejects: %w[first_type])
#
#       @observer = Ractor.new do
#         Ractor.yield Ractor.receive
#       end
#       @pipe.notify "first_type"
#       @pipe.notify "second_type"
#       @pipe.notify "third_type"
#
#       # first_type is omitted
#       expect(@observer.take.type).to eq "second_type"
#       expect(@observer.take.type).to eq "third_type"
#     end
#   end
# end
