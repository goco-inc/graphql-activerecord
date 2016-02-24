module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::DefinitionHelpers::TypeDefiner.instance
      end

      def self.traverse_path(base_model, path, context)
        model = base_model
        path.each do |segment|
          return nil unless model
          model = model.public_send(segment)
        end

        return model
      end

      # Detects the values that are valid for an attribute by looking at the inclusion validators
      def self.detect_inclusion_values(model_type, attribute)
        # Get all of the inclusion validators
        validators = model_type.validators_on(attribute).select { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }

        # Ignore any inclusion validators that are using the 'if' or 'unless' options
        validators = validators.reject { |v| v.options.include?(:if) || v.options.include?(:unless) || v.options[:in].blank? }
        return nil unless validators.any?
        return validators.map { |v| v.options[:in] }.reduce(:&)
      end

      # Defines a special attribute field (eg, 'attachment')
      def self.define_attribute_type_field(definer, model_type, path, attr_type, field_name, options)
        camel_name = options[:name] || field_name.to_s.camelize(:lower).to_sym

        definer.field camel_name, attr_type.graph_type_proc do
          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)
            return nil unless model
            return nil unless context.can?(:read, model)

            return attr_type.resolve(model, field_name)
          end
        end
      end
    end
  end
end
