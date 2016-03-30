require 'ostruct'

module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::Define::TypeDefiner.instance
      end

      # Returns a promise that will eventually resolve to the model that is at the end of the path
      def self.load_and_traverse(current_model, path, context)
        cache_model(context, current_model)
        return Promise.resolve(current_model) if path.length == 0 || current_model.nil?

        association = current_model.association(path[0])

        while path.length > 0 && (association.loaded? || attempt_cache_load(current_model, association, context))
          current_model = association.target
          path = path[1..-1]
          cache_model(context, current_model)

          return Promise.resolve(current_model) if path.length == 0 || current_model.nil?

          association = current_model.association(path[0])
        end

        request = AssociationLoadRequest.new(current_model, path[0], context)
        Loader.for(request.target_class).load(request).then do |next_model|
          next next_model if next_model.blank?
          cache_model(context, next_model)

          if path.length == 1
            sanity = next_model.is_a?(Array) ? next_model[0] : next_model
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

      # Defines a special computed field (eg, 'attachment')
      def self.define_computed_type_field(graph_type, path, computed_type, field_args, options)
        graph_model_type = graph_type.instance_variable_get(:@model_type)

        camel_name = options[:name] || field_args[0].to_s.camelize(:lower).to_sym

        # Verify that the arguments provided are all valid identifiers
        invalid = field_args.select do |arg|
          arg_string = arg.to_s
          unless GraphQL::Models::Identification::VALID_IDENTIFIER_EXP === arg_string
            fail ArgumentError.new("Computed fields can only take arguments that are valid identifiers ([a-z][a-z0-9_]+) when casted to string. The argument #{arg.inspect} is not valid for #{computed_type.name} on #{graph_type.name}.")
          end
        end

        field_type = computed_type.graph_type_proc.call(*field_args)
        unless field_type.is_a?(GraphQL::BaseType)
          fail StandardError.new("The graph_type proc for computed type #{computed_type.name} should return a GraphQL::BaseType, but it actually returned #{field_type.class.name}. Check `graph_type` for #{computed_type.name} at #{computed_type.location}.")
        end

        DefinitionHelpers.register_field_metadata(graph_model_type, camel_name, {
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

      # Stores metadata about GraphQL fields that are available on this model's GraphQL type.
      # @param metadata Should be a hash that contains information about the field's definition, including :macro and :type
      def self.register_field_metadata(model_type, field_name, metadata)
        field_name = field_name.to_s

        field_meta = model_type.instance_variable_get(:@_graphql_field_metadata)
        field_meta = model_type.instance_variable_set(:@_graphql_field_metadata, {}) unless field_meta
        field_meta[field_name] = OpenStruct.new(metadata).freeze
      end
    end
  end
end
