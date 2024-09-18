require "rspec/expectations"

# Custom matcher that repeatedly evaluates the block until it matches the expected value or 5 seconds have elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect("Hello").to become_equal_to { subject.greeting }
#
RSpec::Matchers.define :become_equal_to do
  match do |expected|
    wait_for do
      block_arg.call == expected
    end
    true
  rescue Timeout::Error
    false
  end

  failure_message do |expected|
    "expected block to return #{expected} but was #{@result} after timeout expired"
  end
end
