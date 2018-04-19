# frozen_string_literal: true

module GraphQL::Models
  module MutationHelpers
    class ValidationError < GraphQL::ExecutionError
      attr_accessor :invalid_arguments, :unknown_errors

      def initialize(invalid_arguments, unknown_errors)
        @invalid_arguments = invalid_arguments
        @unknown_errors = unknown_errors
      end

      def to_h
        values = {
          'message' => "Some of your changes could not be saved.",
          'kind' => "INVALID_ARGUMENTS",
          'invalidArguments' => invalid_arguments,
          'unknownErrors' => unknown_errors,
        }

        if ast_node
          values['locations'] = [{
            "line" => ast_node.line,
            "column" => ast_node.col,
          },]
        end

        values
      end

      def to_s
        "Some of your changes could not be saved."
      end
    end
  end
end
