require "spec_helper"
require_relative "a_pipe"
require "async"

RSpec.describe Plumbing::Pipe do
  Plumbing::Spec.modes do
    context "In #{Plumbing.config.mode} mode" do
      it_behaves_like "a pipe"
    end
  end
end
