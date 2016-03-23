module GraphQL
  module Models
    module Identification
      # If you're using a singleton 'viewer' field, you can use this for it's underlying object and global ID
      VIEWER_OBJECT = VIEWER_ID = "AAAAAAAAAAAAAAAAAAAAAHZpZXdlcg=="

      def self.register_attribute_type(&block)
        attr_type = AttributeTypeDefinition.define(&block)
        ATTRIBUTE_TYPES[attr_type.name] = attr_type

        # Create a method for defining this type of object inside of a schema
        GraphQL::ObjectType.accepts_definitions({
          :"#{attr_type.name}" => lambda do |graph_type, field_name, **options|
            DefinitionHelpers.define_attribute_type_field(graph_type, [], attr_type, field_name, options)
          end
        })

        ProxyBlock.send(:define_method, "#{attr_type.name}") do |field_name, **options|
          DefinitionHelpers.define_attribute_type_field(@graph_type, @path, attr_type, field_name, options)
        end

        # Create a method for generating a global ID for this type
        define_singleton_method("#{attr_type.name}_id") do |model_type, model_id, field_name|
          [model_type, field_name].reject { |v| VALID_IDENTIFIER_EXP === v.to_s }.each do |value|
            fail ArgumentError, "The value '#{value}' is not valid inside of a global ID"
          end

          type_name = "#{attr_type.name}(#{model_type},#{field_name})"
          GraphQL::Relay::GlobalNodeIdentification.to_global_id(type_name, model_id)
        end
      end
    end
  end
end
