module Plumbing
  module Pipeline
    # Validate input and output data with pre and post conditions or [Dry::Validation::Contract]s
    module Contracts
      # @param name [Symbol] the name of the precondition
      # @param &validator [Block] a block that returns a boolean value - true to accept the input, false to reject it
      # @yield [Object] input the input data to be validated
      # @yieldreturn [Boolean] true to accept the input, false to reject it
      def pre_condition name, &validator
        pre_conditions[name.to_sym] = validator
      end

      # @param [String] contract_class the class name of the [Dry::Validation::Contract] that will be used to validate the input data
      def validate_with contract_class
        @validation_contract = contract_class
      end

      # @param name [Symbol] the name of the postcondition
      # @param &validator [Block] a block that returns a boolean value - true to accept the input, false to reject it
      # @yield [Object] output the output data to be validated
      # @yieldreturn [Boolean] true to accept the output, false to reject it
      def post_condition name, &validator
        post_conditions[name.to_sym] = validator
      end

      private

      def pre_conditions
        @pre_conditions ||= {}
      end

      def post_conditions
        @post_conditions ||= {}
      end

      def validate_contract_for input
        return true if @validation_contract.nil?
        result = const_get(@validation_contract).new.as(Callable).call(input)
        raise PreConditionError, result.errors.to_h.to_yaml unless result.success?
        input
      end

      def validate_preconditions_for input
        failed_preconditions = pre_conditions.select { |name, validator| !validator.as(Callable).call(input) }
        raise PreConditionError, failed_preconditions.keys.join(", ") if failed_preconditions.any?
        input
      end

      def validate_postconditions_for output
        failed_postconditions = post_conditions.select { |name, validator| !validator.as(Callable).call(output) }
        raise PostConditionError, failed_postconditions.keys.join(", ") if failed_postconditions.any?
        output
      end
    end
  end
end
