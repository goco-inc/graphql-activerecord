# frozen_string_literal: true

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
        validators.map { |v| v.options[:in] }.reduce(:&)
      end

      # Determines if the attribute (or association) is required by examining presence validators
      # and the nullability of the column in the database
      def is_required(model_class, attr_or_assoc)
        # Check for non-nullability on the column itself
        return true if model_class.columns_hash[attr_or_assoc.to_s]&.null == false

        # Check for a presence validator on the association
        return true if model_class.validators_on(attr_or_assoc)
          .select { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
          .reject { |v| v.options.include?(:if) || v.options.include?(:unless) }
          .any?

        # If it's a belongs_to association, check for nullability on the foreign key
        reflection = model_class.reflect_on_association(attr_or_assoc)
        return true if reflection && reflection.macro == :belongs_to && is_required(model_class, reflection.foreign_key)

        false
      end

      # Returns a struct that tells you the input and output GraphQL types for an attribute
      def attribute_graphql_type(model_class, attribute)
        # See if it's an enum
        if model_class.graphql_enum_types.include?(attribute)
          type = model_class.graphql_enum_types[attribute]
          DatabaseTypes::TypeStruct.new(type, type)
        else
          # See if it's a registered scalar type
          active_record_type = model_class.type_for_attribute(attribute.to_s)

          if active_record_type.type.nil?
            raise ArgumentError, "The type for attribute #{attribute} wasn't found on #{model_class.name}"
          end

          result = DatabaseTypes.registered_type(active_record_type.type)

          if result.nil? && GraphQL::Models.unknown_scalar
            type = GraphQL::Models.unknown_scalar.call(active_record_type.type, model_class, attribute)

            if type.is_a?(GraphQL::BaseType) && (type.unwrap.is_a?(GraphQL::ScalarType) || type.unwrap.is_a?(GraphQL::EnumType))
              result = DatabaseTypes::TypeStruct.new(type, type)
            elsif type.is_a?(DatabaseTypes::TypeStruct)
              result = type
            else
              raise "Got unexpected value #{type.inspect} from `unknown_scalar` proc. Expected a GraphQL::ScalarType, GraphQL::EnumType, or GraphQL::Models::DatabaseTypes::TypeStruct."
            end
          end

          if result.nil?
            # rubocop:disable Metrics/LineLength
            raise "Don't know how to map database type #{active_record_type.type.inspect} to a GraphQL type. Forget to register it with GraphQL::Models::DatabaseTypes? (attribute #{attribute} on #{model_class.name})"
            # rubocop:enable Metrics/LineLength
          end

          # Arrays: Rails doesn't have a generalized way to detect arrays, so we use this method to do it:
          if active_record_type.class.name.ends_with?('Array')
            DatabaseTypes::TypeStruct.new(result.input.to_list_type, result.output.to_list_type)
          else
            result
          end
        end
      end
    end
  end
end
