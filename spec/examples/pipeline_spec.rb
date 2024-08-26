require "spec_helper"

RSpec.describe "Pipeline examples" do
  it "builds a simple pipeline of operations adding to an array with pre-conditions and post-conditions" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class BuildArray < Plumbing::Pipeline
      perform :add_first
      perform :add_second
      perform :add_third

      pre_condition :must_be_an_array do |input|
        input.is_a? Array
      end

      post_condition :must_have_three_elements do |output|
        output.length == 3
      end

      private

      def add_first(input) = input << "first"

      def add_second(input) = input << "second"

      def add_third(input) = input << "third"
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(BuildArray.new.call([])).to eq ["first", "second", "third"]
    expect { BuildArray.new.call(1) }.to raise_error(Plumbing::PreConditionError)
    expect { BuildArray.new.call(["extra element"]) }.to raise_error(Plumbing::PostConditionError)
  end

  it "builds a simple pipeline of operations using an external class to implement one of the steps" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class ExternalStep < Plumbing::Pipeline
      perform :add_item_to_array

      private

      def add_item_to_array(input) = input << "external"
    end

    class BuildSequenceWithExternalStep < Plumbing::Pipeline
      perform :add_first
      perform :add_second, using: "ExternalStep"
      perform :add_third

      private

      def add_first(input) = input << "first"

      def add_third(input) = input << "third"
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(BuildSequenceWithExternalStep.new.call([])).to eq ["first", "external", "third"]
  end
end
