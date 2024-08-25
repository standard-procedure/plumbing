module Plumbing
  class Pipeline
    module Operations
      def perform method, &implementation
        implementation ||= ->(input, instance) { instance.send(method, input) }
        operations << implementation
      end

      def embed method, class_name
        implementation = ->(input, instance) { const_get(class_name).new.call(input) }
        operations << implementation
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
          result = operation.call(result, instance)
        end
        validate_postconditions_for result
        result
      end

      private

      def operations
        @operations ||= []
      end
    end
  end
end
