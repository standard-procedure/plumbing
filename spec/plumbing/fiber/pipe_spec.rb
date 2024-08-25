require "spec_helper"
require "async"
require "plumbing/fiber/pipe"
require_relative "../a_pipe"

RSpec.describe Plumbing::Fiber::Pipe do
  around :example do |example|
    Sync(&example)
  end

  it_behaves_like "a pipe"
end
