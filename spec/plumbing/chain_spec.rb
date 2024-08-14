require "spec_helper"

require "plumbing/chain"

RSpec.describe Plumbing::Chain do
  it "defines a single operation that returns a value based upon the input parameters" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Addition < Plumbing::Chain
      perform :addition

      private

      def addition number
        number + 1
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(Addition.new.call(5)).to eq 6
  end

  it "raises a PreconditionError if the input fails the precondition test" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class PreConditionCheck < Plumbing::Chain
      pre_condition :has_first_key do |params|
        params.key?(:first)
      end

      pre_condition :has_second_key do |params|
        params.key?(:second)
      end

      perform :do_something

      private

      def do_something params
        "#{params[:first]} #{params[:second]}"
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(PreConditionCheck.new.call(first: "First", second: "Second")).to eq "First Second"
    expect { PreConditionCheck.new.call(first: "First") }.to raise_error(Plumbing::PreConditionError, "has_second_key")
  end

  it "raises a PostconditionError if the outputs fail the postcondition test" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class PostConditionCheck < Plumbing::Chain
      post_condition :should_be_integer do |result|
        result.instance_of? Integer
      end

      post_condition :should_be_greater_than_zero do |result|
        result > 0
      end

      perform :do_something

      private

      def do_something value
        value.to_i
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(PostConditionCheck.new.call("23")).to eq 23
    expect { PostConditionCheck.new.call("NOT A NUMBER") }.to raise_error(Plumbing::PostConditionError, "should_be_greater_than_zero")
  end

  it "defines a sequence of commands that are executed in order" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Sequence < Plumbing::Chain
      perform :first_step
      perform :second_step
      perform :third_step

      private

      def first_step value = []
        value << "first"
      end

      def second_step value = []
        value << "second"
      end

      def third_step value = []
        value << "third"
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(Sequence.new.call([])).to eq ["first", "second", "third"]
  end

  it "embeds an external command within a sequence of commands" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Embedded < Plumbing::Chain
      perform :embedded_step

      private

      def embedded_step value = []
        value << "embedded"
      end
    end

    class Outer < Plumbing::Chain
      perform :first_step
      perform :second_step do |params|
        Embedded.new.call(params)
      end
      perform :third_step

      private

      def first_step value = []
        value << "first"
      end

      def third_step value = []
        value << "third"
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(Outer.new.call([])).to eq ["first", "embedded", "third"]
  end
end
