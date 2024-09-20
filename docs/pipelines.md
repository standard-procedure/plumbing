# Plumbing::Pipeline - transform data through a pipeline

Define a sequence of operations that proceed in order, passing their output from one operation as the input to another.  [Unix pipes](https://en.wikipedia.org/wiki/Pipeline_(Unix)) in Ruby.

- Use `perform` to define a step that takes some input and returns a different output.
  - Specify `using` to re-use an existing `Plumbing::Pipeline` as a step within this pipeline.
- Use `execute` to define a step that takes some input, performs an action but passes the input, unchanged, to the next step.

If you have [dry-validation](https://dry-rb.org/gems/dry-validation/1.10/) installed, you can validate your input using a `Dry::Validation::Contract`.  Alternatively, you can define a `pre_condition` to test that the inputs are valid.

You can also verify that the output generated is as expected by defining a `post_condition`.

Also take a look at [pipes vs pipelines](/docs/pipes_vs_pipelines.md).

## Usage:

[Building an array using multiple steps with a pre-condition and post-condition](/spec/examples/pipeline_spec.rb)

```ruby
  require "plumbing"
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

  BuildArray.new.call []
  # => ["first", "second", "third"]

  BuildArray.new.call 1
  # => Plumbing::PreconditionError("must_be_an_array")

  BuildArray.new.call ["extra element"]
  # => Plumbing::PostconditionError("must_have_three_elements")
```

[Validating input parameters with a contract](/spec/examples/pipeline_spec.rb)
```ruby
  require "plumbing"
  require "dry/validation"

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

  SayHello.new.call(name: "Alice", email: "alice@example.com")
  # => Hello Alice - I will now send a load of annoying marketing messages to alice@example.com

  SayHello.new.call(some: "other data")
  # => Plumbing::PreConditionError
```

[Building a pipeline through composition](/spec/examples/pipeline_spec.rb)

```ruby
  require "plumbing"
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

  BuildSequenceWithExternalStep.new.call([])
  # => ["first", "external", "third"]
```
