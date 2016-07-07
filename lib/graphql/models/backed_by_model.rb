module GraphQL
  module Models
    class BackedByModel
      attr_accessor :graph_type, :model_type, :object_to_model

      DEFAULT_OBJECT_TO_MODEL = -> (obj) { obj }

      def initialize(graph_type, model_type)
        @graph_type = graph_type
        @model_type = model_type
        @object_to_model = DEFAULT_OBJECT_TO_MODEL
      end

      def types
        GraphQL::Define::TypeDefiner.instance
      end

      def object_to_model(value = nil)
        @object_to_model = value if value
        @object_to_model
      end

      def attr(name, **options, &block)
        DefinitionHelpers.define_attribute(graph_type, model_type, model_type, [], name, object_to_model, options, &block)
      end

      def proxy_to(association, &block)
        DefinitionHelpers.define_proxy(graph_type, model_type, model_type, [], association, object_to_model, &block)
      end

      def has_one(association, **options)
        DefinitionHelpers.define_has_one(graph_type, model_type, model_type, [], association, object_to_model, options)
      end

      def has_many_connection(association, **options)
        DefinitionHelpers.define_has_many_connection(graph_type, model_type, model_type, [], association, object_to_model, options)
      end

      def has_many_array(association, **options)
        DefinitionHelpers.define_has_many_array(graph_type, model_type, model_type, [], association, object_to_model, options)
      end

      def field(*args, &block)
        defined_field = GraphQL::Define::AssignObjectField.call(graph_type, *args, &block)

        DefinitionHelpers.register_field_metadata(graph_type, defined_field.name, {
          macro: :field,
          macro_type: :custom,
          path: [],
          base_model_type: @model_type.to_s.classify.constantize,
          model_type: @model_type.to_s.classify.constantize,
          object_to_base_model: object_to_model
        })

        defined_field
      end
    end
  end
end
