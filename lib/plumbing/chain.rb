module Plumbing
  # A chain of operations that are executed in sequence
  class Chain
    def call input
      self.class._call input, self
    end

    class << self
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

      def pre_condition name, &validator
        pre_conditions[name.to_sym] = validator
      end

      def validate_with contract_class
        @validation_contract = contract_class
      end

      def post_condition name, &validator
        post_conditions[name.to_sym] = validator
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

      def pre_conditions
        @pre_conditions ||= {}
      end

      def post_conditions
        @post_conditions ||= {}
      end

      def validate_contract_for input
        return true if @validation_contract.nil?
        result = const_get(@validation_contract).new.call(input)
        raise PreConditionError, result.errors.to_h.to_yaml unless result.success?
        input
      end

      def validate_preconditions_for input
        failed_preconditions = pre_conditions.select { |name, validator| !validator.call(input) }
        raise PreConditionError, failed_preconditions.keys.join(", ") if failed_preconditions.any?
        input
      end

      def validate_postconditions_for output
        failed_postconditions = post_conditions.select { |name, validator| !validator.call(output) }
        raise PostConditionError, failed_postconditions.keys.join(", ") if failed_postconditions.any?
        output
      end
    end
  end
end
