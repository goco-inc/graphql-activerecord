# Exposes utility methods for getting metadata out of active record models
module GraphQL::Models
  module Reflection
    class << self
      # Returns the possible values for an attribute on a model by examining inclusion validators
      def possible_values(model_class, attribute)
        # Get all of the inclusion validators
        validators = model_class.validators_on(attribute).select { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }

        # Ignore any inclusion validators that are using the 'if' or 'unless' options
        validators = validators.reject { |v| v.options.include?(:if) || v.options.include?(:unless) || v.options[:in].blank? }
        return nil unless validators.any?
        return validators.map { |v| v.options[:in] }.reduce(:&)
      end

      # Determines if the attribute (or association) is required by examining presence validators
      def is_required(model_class, attr_or_assoc)
        model_class.validators_on(attr_or_assoc)
          .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
          .reject { |v| v.options.include?(:if) || v.options.include?(:unless) }
          .any?
      end

      # Returns a struct that tells you the input and output GraphQL types for an attribute
      def attribute_graphql_type(model_class, attribute)
        # See if it's an enum
        if model_class.graphql_enum_types.include?(attribute)
          type = model_class.graphql_enum_types[attribute]
          DatabaseTypes::TypeStruct.new(type, type)
        else
          # See if it's a registered scalar type
          active_record_type = model_class.type_for_attribute(attribute.to_s).type

          if active_record_type.nil?
            fail ArgumentError, "The type for attribute #{attribute} wasn't found on #{model_class.name}"
          end

          result = DatabaseTypes.registered_type(active_record_type)

          if !result
            fail RuntimeError, "The type #{active_record_type} is not registered with DatabaseTypes (attribute #{attribute} on #{model_class.name})"
          end

          result
        end
      end
    end
  end
end
