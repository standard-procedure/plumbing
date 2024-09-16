require "spec_helper"
require "plumbing/actor/async"
require "plumbing/actor/threaded"

RSpec.describe "await" do
  # standard:disable Lint/ConstantDefinitionInBlock
  class Person
    include Plumbing::Actor
    async :name
    def initialize name
      @name = name
    end
    attr_reader :name
  end
  # standard:enable Lint/ConstantDefinitionInBlock

  [:inline, :async, :threaded].each do |mode|
    context "#{mode} mode" do
      around :example do |example|
        Sync do
          Plumbing.configure mode: mode, &example
        end
      end

      it "awaits a result from the actor directly" do
        @person = Person.start "Alice"

        expect(@person.name.value).to eq "Alice"
      end

      it "uses a block to await the result from the actor" do
        @person = Person.start "Alice"

        expect(await { @person.name }).to eq "Alice"
      end

      it "uses a block to immediately access non-actor objects" do
        @person = "Bob"
        expect(await { @person }).to eq "Bob"
      end
    end
  end
end
