module Plumbing
  class Pipeline
    module Operations
      def perform method, using: nil, &implementation
        using.nil? ? perform_internal(method, &implementation) : perform_external(method, using)
      end

      def execute method
        implementation ||= ->(input, instance) do
          instance.send(method, input)
          input
        end
        operations << implementation
      end

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
