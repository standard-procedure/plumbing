module Plumbing
  module Pipeline
    # Defining the operations that will be performed on the input data
    module Operations
      # Add an operation to the pipeline
      # Operations are processed in order, unless interrupted by an exception
      # The output from the previous operation is fed in as the input to the this operation
      # and the output from this operation is fed in as the input to the next operation
      #
      # @param method [Symbol] the method to be called on the input data
      # @param using [String, Class] the optional class name or class that will be used to perform the operation
      # @param &implementation [Block] the optional block that will be used to perform the operation (instead of calling a method)
      # @yield [Object] input the input data to be processed
      # @yieldreturn [Object] the output data
      def perform method, using: nil, &implementation
        using.nil? ? perform_internal(method, &implementation) : perform_external(method, using)
      end

      # Add an operation which does not alter the input data to the pipeline
      # The output from the previous operation is fed in as the input to the this operation
      # but the output from this operation is discarded and the previous input is fed in to the next operation
      #
      # @param method [Symbol] the method to be called on the input data
      def execute method
        implementation ||= ->(input, instance) do
          instance.send(method, input)
          input
        end
        operations << implementation
      end

      # Internal use only
      def _call input, instance
        validate_contract_for input
        validate_preconditions_for input
        result = input
        operations.each do |operation|
          result = operation.as(Callable).call(result, instance)
        end
        validate_postconditions_for result
        result
      end

      private

      def operations
        @operations ||= []
      end

      def perform_internal method, &implementation
        implementation ||= ->(input, instance) { instance.send(method, input) }
        operations << implementation
      end

      def perform_external method, class_or_class_name
        external_class = class_or_class_name.is_a?(String) ? const_get(class_or_class_name) : class_or_class_name
        implementation = ->(input, instance) { external_class.new.as(Callable).call(input) }
        operations << implementation
      end
    end
  end
end
