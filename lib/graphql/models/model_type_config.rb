module GraphQL
  module Models
    class ModelTypeConfig < GraphQL::DefinitionHelpers::DefinedByConfig::DefinitionConfig
      attr_definable :model_type

      def resolved_model_type
        return nil unless @model_type
        @model_type.to_s.classify.constantize
      end

      def standard_fields
        noauth_field :id, field: GraphQL::Relay::GlobalIdField.new(name)
        interfaces [NodeIdentification.interface]

        noauth_field :rid, !types.String do
          resolve proc { |model| model.id }
        end

        noauth_field :rtype, !types.String do
          resolve proc { |model| model.class.name }
        end

        attr :created_at
        attr :updated_at
      end

      def interfaces(new_value = nil)
        if new_value
          @interfaces = [*@interfaces, new_value].flatten.uniq.compact
        end

        @interfaces
      end

      alias_method :noauth_field, :field

      def field(*outer_args)
        field = super

        resolver = field.resolve_proc
        field.resolve = -> (model, args, context) do
          context.authorize!(:read, model)
          resolver.call(model, args, context)
        end

        field
      end

      def proxy_to(association, &block)
        fail ApiExceptions::InvalidOperationError.new("You must call model_type before using the #{__method__} method.") unless resolved_model_type
        DefinitionHelpers.define_proxy(self, resolved_model_type, [], association, &block)
      end

      # Adds a field to the GraphQL type by looking up an attribute on the model. The name of the field will be
      # a camelized version of the attribute name.
      def ensure_has_model_type(method)
        fail ApiExceptions::InvalidOperationError.new("You must call model_type before using the #{method} method.") unless resolved_model_type
      end

      def attr(name, **options)
        ensure_has_model_type(__method__)
        DefinitionHelpers.define_attribute(self, resolved_model_type, [], name, options)
      end

      # def attachment(name, **options)
      #   ensure_has_model_type(__method__)
      #   DefinitionHelpers.define_attachment(self, resolved_model_type, [], name, options)
      # end

      def has_one(association, **options)
        ensure_has_model_type(__method__)
        DefinitionHelpers.define_has_one(self, resolved_model_type, [], association, options)
      end

      def has_many_connection(association, **options)
        ensure_has_model_type(__method__)
        DefinitionHelpers.define_has_many_connection(self, resolved_model_type, [], association, options)

      end

      def has_many_array(association, **options)
        ensure_has_model_type(__method__)
        DefinitionHelpers.define_has_many_array(self, resolved_model_type, [], association, options)
      end
    end
  end
end
