# frozen_string_literal: true

module GraphQL
  module Models
    class BackedByModel
      DEFAULT_OBJECT_TO_MODEL = -> (obj) { obj }

      def initialize(graph_type, model_type, base_model_type: model_type, path: [], object_to_model: DEFAULT_OBJECT_TO_MODEL, detect_nulls: true)
        model_type = model_type.to_s.classify.constantize unless model_type.is_a?(Class)
        base_model_type = base_model_type.to_s.classify.constantize unless model_type.is_a?(Class)

        @graph_type = graph_type
        @model_type = model_type
        @object_to_model = object_to_model
        @base_model_type = base_model_type
        @path = path
        @detect_nulls = detect_nulls
      end

      def types
        GraphQL::Define::TypeDefiner.instance
      end

      def object_to_model(value = nil)
        @object_to_model = value if value
        @object_to_model
      end

      # Allows you to overide the automatic nullability detection. By default, nulls are detected. However, attributes inside
      # of a proxy_to block are assumed to be nullable, unless the association itself has a presence validator.
      def detect_nulls(value = nil)
        @detect_nulls = value if !value.nil?
        @detect_nulls
      end

      # Adds a field to the graph type that is resolved to an attribute on the model.
      # @param attribute Symbol with the name of the attribute on the model
      # @param description Description for the field
      # @param name Name of the field to use. By default, the attribute name is camelized.
      # @param nullable Set to false to force the field to be non-null. By default, nullability is automatically detected.
      # @param deprecation_reason Sets the deprecation reason on the field.
      def attr(attribute, name: attribute.to_s.camelize(:lower), nullable: nil, description: nil, deprecation_reason: nil, &block)
        name = name.to_sym unless name.is_a?(Symbol)

        # Get the description from the column, if it's not provided. Doesn't work in Rails 4 :(
        unless description
          column = @model_type.columns_hash[attribute.to_s]
          description = column.comment if column&.respond_to?(:comment)
        end

        options = {
          name: name,
          nullable: nullable,
          description: description,
          deprecation_reason: deprecation_reason,
        }

        DefinitionHelpers.define_attribute(@graph_type, @base_model_type, @model_type, @path, attribute, @object_to_model, options, @detect_nulls, &block)
      end

      # Flattens an associated model into the graph type, allowing to you adds its attributes as if they existed on the parent model.
      # @param association Name of the association to use. Polymorphic belongs_to associations are not supported.
      def proxy_to(association, &block)
        DefinitionHelpers.define_proxy(@graph_type, @base_model_type, @model_type, @path, association, @object_to_model, @detect_nulls, &block)
      end

      def has_one(association, name: association.to_s.camelize(:lower), nullable: nil, description: nil, deprecation_reason: nil)
        name = name.to_sym unless name.is_a?(Symbol)

        options = {
          name: name,
          nullable: nullable,
          description: description,
          deprecation_reason: deprecation_reason,
        }

        DefinitionHelpers.define_has_one(@graph_type, @base_model_type, @model_type, @path, association, @object_to_model, options, @detect_nulls)
      end

      def has_many_connection(association, name: association.to_s.camelize(:lower), nullable: nil, description: nil, deprecation_reason: nil, **goco_options)
        name = name.to_sym unless name.is_a?(Symbol)

        options = goco_options.merge({
          name: name,
          nullable: nullable,
          description: description,
          deprecation_reason: deprecation_reason,
        })

        DefinitionHelpers.define_has_many_connection(@graph_type, @base_model_type, @model_type, @path, association, @object_to_model, options, @detect_nulls)
      end

      def has_many_array(association, name: association.to_s.camelize(:lower), nullable: nil, description: nil, deprecation_reason: nil, type: nil)
        name = name.to_sym unless name.is_a?(Symbol)

        options = {
          name: name,
          type: type,
          nullable: nullable,
          description: description,
          deprecation_reason: deprecation_reason,
        }

        DefinitionHelpers.define_has_many_array(@graph_type, @base_model_type, @model_type, @path, association, @object_to_model, options, @detect_nulls)
      end

      def field(*args, &block)
        defined_field = GraphQL::Define::AssignObjectField.call(@graph_type, *args, &block)
        name = defined_field.name
        name = name.to_sym unless name.is_a?(Symbol)

        DefinitionHelpers.register_field_metadata(@graph_type, name, {
          macro: :field,
          macro_type: :custom,
          path: @path,
          base_model_type: @base_model_type,
          model_type: @model_type,
          object_to_base_model: @object_to_model,
        })

        defined_field
      end
    end
  end
end
