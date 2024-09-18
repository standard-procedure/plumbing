require "rspec/expectations"

# Custom matcher that repeatedly evaluates the block until it matches the expected value or the timeout has elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect{ subject.greeting }.to become "Hello Alice"
#
RSpec::Matchers.define :become do |expected|
  match do |block|
    wait_for do
      (@result = block.call) == expected
    end
    true
  rescue Timeout::Error
    false
  end

  def supports_block_expectations? = true

  failure_message do |expected|
    "expected #{expected} but, after timeout, the result was #{@result}"
  end
end

# Custom matcher that repeatedly evaluates the block until it becomes true or the timeout has elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect { @object.valid? }.to become_true
#
RSpec::Matchers.define :become_true do
  match do |block|
    wait_for do
      block.call == true
    end
    true
  rescue Timeout::Error
    false
  end

  def supports_block_expectations? = true

  failure_message do |expected|
    "expected true but timeout expired"
  end
end

# Custom matcher that repeatedly evaluates the block until it becomes truthy or the timeout has elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect { @object.message }.to become_truthy
#
RSpec::Matchers.define :become_truthy do
  match do |block|
    wait_for do
      block.call
    end
    true
  rescue Timeout::Error
    false
  end

  def supports_block_expectations? = true

  failure_message do |expected|
    "expected truthy value but timeout expired"
  end
end

# Custom matcher that repeatedly evaluates the block until it becomes false or the timeout has elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect { @object.in_progress? }.to become_false
#
RSpec::Matchers.define :become_false do
  match do |block|
    wait_for do
      block.call == false
    end
    true
  rescue Timeout::Error
    false
  end

  def supports_block_expectations? = true

  failure_message do |expected|
    "expected false but timeout expired"
  end
end

# Custom matcher that repeatedly evaluates the block until it becomes falsey or the timeout has elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect { @object.background_task }.to become_falsey
#
RSpec::Matchers.define :become_falsey do
  match do |block|
    wait_for do
      !block.call
    end
    true
  rescue Timeout::Error
    false
  end

  def supports_block_expectations? = true

  failure_message do |expected|
    "expected falsey but timeout expired"
  end
end
