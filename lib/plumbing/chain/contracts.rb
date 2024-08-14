module Plumbing
  class Chain
    module Contracts
      def pre_condition name, &validator
        pre_conditions[name.to_sym] = validator
      end

      def validate_with contract_class
        @validation_contract = contract_class
      end

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
