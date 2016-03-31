module GraphQL
  module Models
    module Identification
      # If you're using a singleton 'viewer' field, you can use this for it's underlying object and global ID
      VIEWER_OBJECT = VIEWER_ID = "AAAAAAAAAAAAAAAAAAAAAHZpZXdlcg=="

      def self.register_computed_type(&block)
        computed_type = ComputedTypeDefinition.define(&block)
        COMPUTED_TYPES[computed_type.name] = computed_type

        # Create a method for defining this type of object inside of a schema
        GraphQL::ObjectType.accepts_definitions({
          :"#{computed_type.name}" => lambda do |graph_type, *field_args, **options|
            unless field_args.length == computed_type.arity
              fail ArgumentError.new("The computed type #{computed_type.name} requires #{computed_type.arity} arguments, you provided #{field_args.length}.")
            end

            model_type = graph_type.instance_variable_get(:@model_type)
            DefinitionHelpers.define_computed_type_field(graph_type, model_type, [], computed_type, field_args, options)
          end
        })

        ProxyBlock.send(:define_method, "#{computed_type.name}") do |*field_args, **options|
          unless field_args.length == computed_type.arity
            fail ArgumentError.new("The computed type #{computed_type.name} requires #{computed_type.arity} arguments, you provided #{field_args.length}.")
          end

          DefinitionHelpers.define_computed_type_field(@graph_type, @model_type, @path, computed_type, field_args, options)
        end

        # Create a method for generating a global ID for this type
        define_singleton_method("#{computed_type.name}_id") do |model_type, model_id, *field_args|
          unless field_args.length == computed_type.arity
            fail ArgumentError.new("The computed type #{computed_type.name} requires #{computed_type.arity} arguments, you provided #{field_args.length}.")
          end

          [model_type, *field_args].reject { |v| VALID_IDENTIFIER_EXP === v.to_s }.each do |value|
            fail ArgumentError, "The value '#{value}' is not valid inside of a global ID"
          end

          type_name = "#{computed_type.name}(#{model_type},#{field_args.join(',')})"
          GraphQL::Relay::GlobalNodeIdentification.to_global_id(type_name, model_id)
        end
      end
    end
  end
end
