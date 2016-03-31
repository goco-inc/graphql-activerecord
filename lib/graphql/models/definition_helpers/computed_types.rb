module GraphQL
  module Models
    module DefinitionHelpers

      def self.invoke_graph_type_proc(proc, field_args, model_type, options)
        # Look at the parameters that the proc expects. We'll pass in the field args as the mandatory, but if it
        # also takes keyword arguments, we'll pass those in as well.
        keyword_args = {
          model_type: model_type,
          options: options
        }

        arguments = proc.parameters
        explicit_keys = arguments.select { |arg_def| arg_def[0] == :key || arg_def[0] == :keyreq }.map { |arg_def| arg_def[1] }
        takes_optional_keys = arguments.any? { |arg_def| arg_def[0] == :keyrest || arg_def[0] == :rest }

        if takes_optional_keys
          proc.call(*field_args, **keyword_args)
        elsif explicit_keys.any?
          proc.call(*field_args, **keyword_args.slice(*explicit_keys))
        else
          proc.call(*field_args)
        end
      end

      # Defines a special computed field (eg, 'attachment')
      def self.define_computed_type_field(graph_type, model_type, path, computed_type, field_args, options)
        graph_model_type = graph_type.instance_variable_get(:@model_type)

        camel_name = options[:name] || field_args[0].to_s.camelize(:lower).to_sym

        # Verify that the arguments provided are all valid identifiers
        invalid = field_args.select do |arg|
          arg_string = arg.to_s
          unless GraphQL::Models::Identification::VALID_IDENTIFIER_EXP === arg_string
            fail ArgumentError.new("Computed fields can only take arguments that are valid identifiers ([a-z][a-z0-9_]+) when casted to string. The argument #{arg.inspect} is not valid for #{computed_type.name} on #{graph_type.name}.")
          end
        end

        field_type = invoke_graph_type_proc(computed_type.graph_type_proc, field_args, model_type, options)

        unless field_type.is_a?(GraphQL::BaseType)
          fail StandardError.new("The graph_type proc for computed type #{computed_type.name} should return a GraphQL::BaseType, but it actually returned #{field_type.class.name}. Check `graph_type` for #{computed_type.name} at #{computed_type.location}.")
        end

        DefinitionHelpers.register_field_metadata(graph_model_type, graph_type, camel_name, {
          macro: computed_type.name,
          macro_type: :virtual,
          type_proc: -> { field_type },
          path: path,
          options: options
        })

        graph_type.fields[camel_name.to_s] = GraphQL::Field.define do
          name camel_name.to_s
          type field_type
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (base_model, args, context) do
            DefinitionHelpers.load_and_traverse(base_model, path, context).then do |model|
              next nil unless model
              next computed_type.resolve(model, *field_args)
            end
          end
        end
      end

    end
  end
end
