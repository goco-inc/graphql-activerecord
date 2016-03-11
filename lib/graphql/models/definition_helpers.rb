module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::DefinitionHelpers::TypeDefiner.instance
      end

      # Returns a promise that will eventually resolve to the model that is at the end of the path
      def self.load_and_traverse(current_model, path, context)
        cache_model(context, current_model)
        return Promise.resolve(current_model) if path.length == 0

        association = current_model.association(path[0])

        if association.loaded? || attempt_cache_load(current_model, association, context)
          cache_model(context, association.target)
          return Promise.resolve(association.target)
        end

        request = AssociationLoadRequest.new(current_model, path[0], context)
        Loader.for(request.target_class).load(request).then do |next_model|
          next nil unless next_model

          if path.length == 1
            cache_model(context, next_model)
            next next_model
          else
            DefinitionHelpers.load_and_traverse(next_model, path[1..-1], context)
          end
        end
      end

      # Attempts to retrieve the model from the query's cache. If it's found, the association is marked as
      # loaded and the model is added. This only works for belongs_to and has_one associations.
      def self.attempt_cache_load(model, association, context)
        return false unless context

        reflection = association.reflection
        return false unless [:has_one, :belongs_to].include?(reflection.macro)

        if reflection.macro == :belongs_to
          target_id = model.send(reflection.foreign_key)

          # If there isn't an associated model, mark the association loaded and return
          mark_association_loaded(association, nil) and return true if target_id.nil?

          # If the associated model isn't cached, return false
          target = context.cached_models.detect { |m| m.is_a?(association.klass) && m.id == target_id }
          return false unless target

          # Found it!
          mark_association_loaded(association, target)
          return true
        else
          target = context.cached_models.detect do |m|
            m.is_a?(association.klass) && m.send(reflection.foreign_key) == model.id && (!reflection.options.include?[:as] || m.send(reflection.type) == model.class.name)
          end

          return false unless target

          mark_association_loaded(association, target)
          return true
        end
      end

      def self.cache_model(context, model)
        return unless context
        context.cached_models.merge(Array.wrap(model))
      end

      def self.mark_association_loaded(association, target)
        association.loaded!
        association.target = target
        association.set_inverse_instance(target) unless target.nil?
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
