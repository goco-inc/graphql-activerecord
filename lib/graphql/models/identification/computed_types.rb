module GraphQL
  module Models
    module Identification
      VALID_IDENTIFIER = "[a-zA-Z][a-zA-Z0-9_]+"
      VALID_IDENTIFIER_EXP = /\A#{VALID_IDENTIFIER}\z/

      # For a virtual type, the "type_name" part of the ID will look like this:
      # attachment(OfferLetter, signed_document)
      COMPUTED_TYPE_EXP = %r{
        \A
        (?<name>#{VALID_IDENTIFIER}) # match the name of the virtual type
        \(( # parameters, wrapped with parentheses
          (?<modelType>#{VALID_IDENTIFIER}) # type of model that the field was used on
          (?<fieldArgs>(,#{VALID_IDENTIFIER})+) # name of the field
        )\)
        \z
      }x

      COMPUTED_TYPES = {}.with_indifferent_access

      def self.is_computed_type(type_name)
        COMPUTED_TYPE_EXP === type_name
      end

      def self.resolve_computed_type(type_name, model_id, context)
        parsed = parse_computed_type_name(type_name)
        computed_type = parsed[:computed_type]
        field_args = parsed[:field_args]
        model_type = parsed[:model_type]

        return nil unless computed_type.validate(model_type.constantize, *field_args)

        model = resolve_model_type(model_type, model_id, context)
        return nil unless model

        computed_type.resolve(model, *field_args)
      end

      def self.parse_computed_type_name(type_name)
        match = COMPUTED_TYPE_EXP.match(type_name)
        return nil unless COMPUTED_TYPES.include?(match['name']) && is_model_type(match['modelType'])

        computed_type = COMPUTED_TYPES[match['name']]

        field_args = match['fieldArgs'].split(',')[1..-1] # strip off empty element from leading comma
        return nil unless field_args.length == computed_type.arity

        {
          computed_type: computed_type,
          field_args: field_args,
          model_type: match['modelType']
        }
      end

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
