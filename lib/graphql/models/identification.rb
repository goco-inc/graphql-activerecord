module GraphQL
  module Models
    module Identification
      # If you're using a singleton 'viewer' field, you can use this for it's underlying object and global ID
      VIEWER_OBJECT = VIEWER_ID = "AAAAAAAAAAAAAAAAAAAAAHZpZXdlcg=="

      def self.register_attribute_type(&block)
        attr_type = AttributeTypeDefinition.define(&block)
        ATTRIBUTE_TYPES[attr_type.name] = attr_type

        # Create a method for defining this type of object inside of a schema
        

        # Create a method for generating a global ID for this type
        define_singleton_method("#{attr_type.name}_id") do |model_type, model_id, *identifiers|
          missing_identifiers = attr_type.identifiers[identifiers.length..-1]
          fail ArgumentError, "You need to provide #{attr_type.identifiers.length} identifier arguments to generate an ID for #{attr_type.name} (missing: #{missing_identifiers.join(', ')})" unless identifiers.length == attr_type.identifiers.length

          [model_type, *identifiers].reject { |v| VALID_IDENTIFIER_EXP === v.to_s }.each do |value|
            fail ArgumentError, "The value '#{value}' is not valid inside of a global ID"
          end

          params = [model_type, *identifiers]
          type_name = "#{attr_type.name}(#{params.join(',')})"

          GraphQL::Relay::GlobalNodeIdentification.to_global_id(type_name, model_id)
        end
      end
    end
  end
end
