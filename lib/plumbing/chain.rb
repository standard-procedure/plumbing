module Plumbing
  # A chain of operations that are executed in sequence
  class Chain
    def call params
      self.class._call params, self
    end

    class << self
      def pre_condition name, &validator
        pre_conditions[name.to_sym] = validator
      end

      def perform method, &implementation
        implementation ||= ->(params, instance) { instance.send(method, params) }
        operations << implementation
      end

      def post_condition name, &validator
        post_conditions[name.to_sym] = validator
      end

      def _call params, instance
        validate_preconditions_for params
        result = params
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
