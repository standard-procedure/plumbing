require "spec_helper"
require "dry/validation"

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

  it "uses a dry-validation contract to test the input parameters" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class SayHello < Plumbing::Pipeline
      validate_with "SayHello::Input"
      perform :say_hello

      private

      def say_hello input
        "Hello #{input[:name]} - I will now send a load of annoying marketing messages to #{input[:email]}"
      end

      class Input < Dry::Validation::Contract
        params do
          required(:name).filled(:string)
          required(:email).filled(:string)
        end
        rule :email do
          key.failure("must be a valid email") unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match? value
        end
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect { SayHello.new.call(name: "Alice", email: "alice@example.com") }.to_not raise_error(Plumbing::PreConditionError)

    expect { SayHello.new.call(some: "other data") }.to raise_error(Plumbing::PreConditionError)
  end
end
