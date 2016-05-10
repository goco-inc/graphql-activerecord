module GraphQL::Models
  module MutationHelpers
    class ValidationError < GraphQL::ExecutionError
      attr_accessor :invalid_fields, :unknown_errors

      def initialize(invalid_fields, unknown_errors)
        @invalid_fields = invalid_fields
        @unknown_errors = unknown_errors
      end

      def to_h
        values = {
          'message' => "Some of your changes could not be saved.",
          'kind' => "INVALID_ARGUMENTS",
          'invalidArguments' => invalid_fields,
          'unknownErrors' => unknown_errors
        }

        if ast_node
          values.merge!({
            'locations' => [{
              "line" => ast_node.line,
              "column" => ast_node.col,
            }]
          })
        end

        values
      end

      def to_s
        "Some of your changes could not be saved."
      end
    end
  end
end
