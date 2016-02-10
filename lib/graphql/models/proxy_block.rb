module GraphQL
  module Models
    class ProxyBlock
      def initialize(definer, model_type, path)
        @path = path
        @model_type = model_type
        @definer = definer
      end

      def attr(name, **options)
        DefinitionHelpers.define_attribute(@definer, @model_type, @path, name, options)
      end

      def proxy_to(association, &block)
        DefinitionHelpers.define_proxy(@definer, @model_type, @path, association, &block)
      end

      def attachment(name, **options)
        DefinitionHelpers.define_attachment(@definer, @model_type, @path, name, options)
      end

      def has_one(association, **options)
        DefinitionHelpers.define_has_one(@definer, @model_type, @path, association, options)
      end

      def has_many_connection(association, **options)
        DefinitionHelpers.define_has_many_connection(@definer, @model_type, @path, association, options)
      end

      def has_many_array(association, **options)
        DefinitionHelpers.define_has_many_array(@definer, @model_type, @path, association, options)
      end
    end
  end
end
