# frozen_string_literal: true

module Plumbing
  module Actor
    module Properties
      def prop name, type, kind = :keyword, reader: false, writer: false, default: nil, predicate: false, description: nil, &coercion
        super(name, type, kind, reader: false, writer: false, default: default, description: description, &coercion)
        _define_reader_method_for name if reader
        _define_writer_method_for name, type if writer
      end

      def _define_reader_method_for name
        async name do
          calls { instance_variable_get "@#{name}" }
        end
      end

      def _define_writer_method_for name, type
        writer = :"set_#{name}_to"
        async writer do
          param :value, type
          calls { |value:| instance_variable_set "@#{name}", value }
        end
        define_method :"#{name}=" do |value|
          send writer, value: value
        end
      end
    end
  end
end
