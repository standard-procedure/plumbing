require "rspec/expectations"

# Custom matcher that repeatedly evaluates the block until it matches the expected value or 10 seconds have elapsed
#
# This allows asynchronous operations to be tested in a synchronous manner with a timeout
#
# Example:
#     expect("Hello").to become_equal_to { subject.greeting }
#
RSpec::Matchers.define :become_equal_to do
  match do |expected|
    counter = 0
    result = false
    while (counter < 100) && (result == false)
      result = true if block_arg.call == expected
      sleep 0.1
      counter += 1
    end
    result
  end
end
