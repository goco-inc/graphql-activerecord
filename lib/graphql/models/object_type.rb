module GraphQL
  module Models
    module ObjectType
      class << self
        def object_to_model(graph_type, proc)
          graph_type.instance_variable_set(:@object_to_model, proc)
        end

        def model_type(graph_type, model_type)
          model_type = model_type.to_s.classify.constantize unless model_type.is_a?(Class)

          graph_type.instance_variable_set(:@model_type, model_type)

          id_field = GraphQL::Relay::GlobalIdField.new(graph_type.name)
          id_field.name = 'id'
          graph_type.fields['id'] = id_field

          graph_type.interfaces = [*graph_type.interfaces, NodeIdentification.interface].uniq

          graph_type.fields['rid'] = GraphQL::Field.define do
            name 'rid'
            type !types.String
            resolve -> (object, args, context) do
              DefinitionHelpers.object_to_model(graph_type, object).id
            end
          end

          graph_type.fields['rtype'] = GraphQL::Field.define do
            name 'rtype'
            type !types.String
            resolve -> (object, args, context) do
              DefinitionHelpers.object_to_model(graph_type, object).class.name
            end
          end

          DefinitionHelpers.define_attribute(graph_type, model_type, [], :created_at, {})
          DefinitionHelpers.define_attribute(graph_type, model_type, [], :updated_at, {})
        end

        def proxy_to(graph_type, association, &block)
          ensure_has_model_type(graph_type, __method__)
          DefinitionHelpers.define_proxy(graph_type, resolve_model_type(graph_type), [], association, &block)
        end

        def attr(graph_type, name, **options)
          ensure_has_model_type(graph_type, __method__)
          DefinitionHelpers.define_attribute(graph_type, resolve_model_type(graph_type), [], name, options)
        end

        def has_one(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          DefinitionHelpers.define_has_one(graph_type, resolve_model_type(graph_type), [], association, options)
        end

        def has_many_connection(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          DefinitionHelpers.define_has_many_connection(graph_type, resolve_model_type(graph_type), [], association, options)

        end

        def has_many_array(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          DefinitionHelpers.define_has_many_array(graph_type, resolve_model_type(graph_type), [], association, options)
        end

        private

        def resolve_model_type(graph_type)
          graph_type.instance_variable_get(:@model_type)
        end

        def ensure_has_model_type(graph_type, method)
          fail RuntimeError.new("You must call model_type before using the #{method} method.") unless graph_type.instance_variable_get(:@model_type)
        end
      end

      # Attach the methods to ObjectType
      extensions = ObjectType.methods(false).reduce({}) do |memo, method|
        memo[method] = ObjectType.method(method)
        memo
      end

      GraphQL::ObjectType.accepts_definitions(extensions)
    end
  end
end
