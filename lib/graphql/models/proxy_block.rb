module GraphQL
  module Models
    class ProxyBlock
      def initialize(graph_type, model_type, path)
        @path = path
        @model_type = model_type
        @graph_type = graph_type
      end

      def types
        GraphQL::Define::TypeDefiner.instance
      end

      def attr(name, **options)
        DefinitionHelpers.define_attribute(@graph_type, @model_type, @path, name, options)
      end

      def proxy_to(association, &block)
        DefinitionHelpers.define_proxy(@graph_type, @model_type, @path, association, &block)
      end

      def attachment(name, **options)
        DefinitionHelpers.define_attachment(@graph_type, @model_type, @path, name, options)
      end

      def has_one(association, **options)
        DefinitionHelpers.define_has_one(@graph_type, @model_type, @path, association, options)
      end

      def has_many_connection(association, **options)
        DefinitionHelpers.define_has_many_connection(@graph_type, @model_type, @path, association, options)
      end

      def has_many_array(association, **options)
        DefinitionHelpers.define_has_many_array(@graph_type, @model_type, @path, association, options)
      end

      def field(*args, &block)
        defined_field = GraphQL::Define::AssignObjectField.call(@graph_type, *args, &block)

        # Wrap the underlying field's resolve, so that it is injected with the model at the current path
        resolver = defined_field.resolve_proc
        path = @path

        defined_field.resolve = -> (base_model, args, context) do
          GraphQL::Models.load_association(base_model, path, context).then do |model|
            resolver.call(model, args, context)
          end
        end

        defined_field
      end
    end
  end
end
