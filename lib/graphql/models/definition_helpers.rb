module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::DefinitionHelpers::TypeDefiner.instance
      end

      # Returns a promise that will eventually resolve to the model that is at the end of the path
      def self.load_and_traverse(current_model, path, context)
        return Promise.resolve(current_model) if path.length == 0

        request = AssociationLoadRequest.new(current_model, path[0], context)
        Loader.for(request.target_class).load(request).then do |next_model|
          next nil unless next_model
          next next_model if path.length == 1

          DefinitionHelpers.load_and_traverse(next_model, path[1..-1], context)
        end
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

        definer.noauth_field camel_name, attr_type.graph_type_proc do
          resolve -> (base_model, args, context) do
            DefinitionHelpers.load_and_traverse(base_model, path, context).then do |model|
              next nil unless model
              next nil unless context.can?(:read, model)
              next attr_type.resolve(model, field_name)
            end
          end
        end
      end
    end
  end
end
