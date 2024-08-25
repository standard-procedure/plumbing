require "spec_helper"
require_relative "a_pipe"
require "async"

RSpec.describe Plumbing::Pipe do
  context "synchronously dispatching events" do
    it_behaves_like "a pipe", Plumbing::Pipe::SynchronousDispatcher.new
  end

  context "dispatching events with fibers" do
    require_relative "../../lib/plumbing/pipe/fiber_dispatcher"
    around :example do |example|
      Sync(&example)
    end

    it_behaves_like "a pipe", Plumbing::Pipe::FiberDispatcher.new(limit: 2)
  end
end
