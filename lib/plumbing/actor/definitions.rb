# frozen_string_literal: true

module Plumbing
  module Actor
    module Definitions
      # Defines three methods on the instance:
      #   `name` - called from outside the actor, returns a message object that must be `await`ed to access the result
      #   `_name` - runs inside the actor's context and validates the parameters before calling the implementation
      #   `_name_implementation` - the actual implementation of the method
      #
      # Validated params are passed into the `returns` block as keyword
      # parameters, so declare them in the block's parameter list:
      #
      #     class Greeting
      #       include Plumbing::Actor
      #
      #       def initialize(name:) = @name = name
      #
      #       async :say do
      #         param :greeting, String, default: "Hello"
      #         returns { |greeting:| "#{greeting} #{@name}" }
      #       end
      #     end
      #
      #     # Greeting has three methods - `say`, `_say` and `_say_implementation`
      #     #   the latter two called internally within the actor's context
      #
      #     greeting = Greeting.new name: "Alice"
      #     result = greeting.say greeting: "Hi there"
      #     puts result.await # => "Hi there Alice"
      #     # ALTERNATIVE SYNTAX
      #     puts await { greeting.say greeting: "Hi there" }
      def async name, &config
        method = MethodDefinition.new(name: name.to_sym)
        method.instance_eval(&config)
        raise ArgumentError, "async :#{name} requires a `calls { ... }` block" if method.implementation.nil?

        # external async method
        define_method name.to_sym do |sender: nil, **params, &block|
          worker.post name.to_sym, sender: sender, **params, &block
        end

        # internal validator
        define_method :"_#{name}" do |**params, &block|
          validated = method.params_class.new(**params).to_h
          send(:"_#{name}_implementation", **validated, &block)
        end

        # internal implementation
        define_method(:"_#{name}_implementation", &method.implementation)
      end

      class MethodDefinition < Literal::Struct
        include Literal::Types

        prop :name, Symbol, writer: false
        prop :implementation, _Callable?, writer: false
        prop :params_class, Class, writer: false, default: -> { Class.new(Literal::Struct) }

        def param(name, type, *rest, **opts)
          params_class.prop(name, type, *rest, **opts)
        end

        def calls(&implementation)
          @implementation = implementation
        end
      end
    end
  end
end
