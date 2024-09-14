require "spec_helper"
require_relative "a_pipe"
require "async"

RSpec.describe Plumbing::Pipe do
  context "inline" do
    around :example do |example|
      Plumbing.configure mode: :inline, &example
    end

    it_behaves_like "a pipe"
  end

  context "async" do
    around :example do |example|
      Sync do
        Plumbing.configure mode: :async, &example
      end
    end

    it_behaves_like "a pipe"
  end

  context "threaded" do
    around :example do |example|
      Plumbing.configure mode: :threaded, &example
    end

    it_behaves_like "a pipe"
  end
end
