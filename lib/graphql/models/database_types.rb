# frozen_string_literal: true

module GraphQL
  module Models
    module DatabaseTypes
      TypeStruct = Struct.new(:input, :output)

      def self.registered_type(database_type)
        @registered_types ||= {}.with_indifferent_access

        result = @registered_types[database_type]
        return nil if result.nil?

        if !result.input.is_a?(GraphQL::BaseType) || !result.output.is_a?(GraphQL::BaseType)
          input = result.input
          output = result.output

          input = input.call if input.is_a?(Proc)
          output = output.call if output.is_a?(Proc)

          input = input.constantize if input.is_a?(String)
          output = output.constantize if output.is_a?(String)

          TypeStruct.new(input, output)
        else
          result
        end
      end

      def self.register(database_type, output_type, input_type = output_type)
        @registered_types ||= {}.with_indifferent_access
        @registered_types[database_type] = TypeStruct.new(input_type, output_type)
      end
    end

    DatabaseTypes.register(:boolean, GraphQL::BOOLEAN_TYPE)
    DatabaseTypes.register(:integer, GraphQL::INT_TYPE)
    DatabaseTypes.register(:float, GraphQL::FLOAT_TYPE)
    DatabaseTypes.register(:string, GraphQL::STRING_TYPE)
  end
end
