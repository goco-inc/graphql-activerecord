module GraphQL
  module Models
    class BackedByModel
      attr_accessor :graph_type, :model_type, :object_to_model

      def initialize(graph_type, model_type)
        @graph_type = graph_type
        @model_type = model_type
      end

      def types
        GraphQL::Define::TypeDefiner.instance
      end

      def attr(name, **options)
        DefinitionHelpers.define_attribute(graph_type, model_type, model_type, [], name, object_to_model, options)
      end

      def proxy_to(association, &block)
        DefinitionHelpers.define_proxy(graph_type, model_type, model_type, [], association, &object_to_model, block)
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

        # Wrap the underlying field's resolve, so that it is injected with the model at the current path
        internal_resolver = defined_field.resolve_proc
        object_to_model = self.object_to_model # because resolver executes in different context

        defined_field.resolve = -> (object, args, context) do
          model = object_to_model.call(object)
          internal_resolver.call(model, args, context)
        end

        defined_field
      end
    end
  end
end
