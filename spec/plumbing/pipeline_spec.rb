require "spec_helper"
require "dry/validation"

RSpec.describe Plumbing::Pipeline do
  it "defines a single operation that returns a value based upon the input parameters" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Addition < Plumbing::Pipeline
      perform :addition

      private

      def addition number
        number + 1
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(Addition.new.call(5)).to eq 6
  end

  it "defines a sequence of commands that are executed in order" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Sequence < Plumbing::Pipeline
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

  context "embedding an external command" do
    it "specifies the command with a string" do
      # standard:disable Lint/ConstantDefinitionInBlock
      class InnerByName < Plumbing::Pipeline
        perform :embedded_step

        private

        def embedded_step value = []
          value << "embedded"
        end
      end

      class OuterByName < Plumbing::Pipeline
        perform :first_step
        perform :second_step, using: "InnerByName"
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

      expect(OuterByName.new.call([])).to eq ["first", "embedded", "third"]
    end

    it "specifies the command with a class" do
      # standard:disable Lint/ConstantDefinitionInBlock
      class InnerByClass < Plumbing::Pipeline
        perform :embedded_step

        private

        def embedded_step value = []
          value << "embedded"
        end
      end

      class OuterByClass < Plumbing::Pipeline
        perform :first_step
        perform :second_step, using: InnerByClass
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

      expect(OuterByClass.new.call([])).to eq ["first", "embedded", "third"]
    end
  end

  it "defines an operation that does something but returns the provided input untouched" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Passthrough < Plumbing::Pipeline
      execute :external_operation

      private

      def external_operation input
        # SomeApi.do_some_stuff input
        nil
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(Passthrough.new.call("some parameters")).to eq "some parameters"
  end

  it "raises a PreconditionError if the input fails the precondition test" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class PreConditionCheck < Plumbing::Pipeline
      pre_condition :has_first_key do |input|
        input.key?(:first)
      end

      pre_condition :has_second_key do |input|
        input.key?(:second)
      end

      perform :do_something

      private

      def do_something input
        "#{input[:first]} #{input[:second]}"
      end
    end
    # standard:enable Lint/ConstantDefinitionInBlock

    expect(PreConditionCheck.new.call(first: "First", second: "Second")).to eq "First Second"
    expect { PreConditionCheck.new.call(first: "First") }.to raise_error(Plumbing::PreConditionError, "has_second_key")
  end

  it "raises a PreconditionError if the input fails to validate against a Dry::Validation::Contract" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class Validated < Plumbing::Pipeline
      validate_with "Validated::Input"
      perform :say_hello

      private

      def say_hello input
        "Hello #{input[:name]} (#{input[:email]})"
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

    expect(Validated.new.call(name: "Alice", email: "alice@example.com")).to eq "Hello Alice (alice@example.com)"
    expect { Validated.new.call(email: "alice@example.com") }.to raise_error(Plumbing::PreConditionError, {name: ["is missing"]}.to_yaml)
    expect { Validated.new.call(name: "Bob", email: "bob-has-fat-fingers-and-cant-type") }.to raise_error(Plumbing::PreConditionError, {email: ["must be a valid email"]}.to_yaml)
  end

  it "raises a PostconditionError if the outputs fail the postcondition test" do
    # standard:disable Lint/ConstantDefinitionInBlock
    class PostConditionCheck < Plumbing::Pipeline
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
end
