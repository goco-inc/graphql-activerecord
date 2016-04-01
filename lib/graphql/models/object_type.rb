module GraphQL
  module Models
    module ObjectType
      class << self
        DEFAULT_OBJECT_TO_MODEL = -> (object) { object }

        def object_to_model(graph_type, model_proc)
          graph_type.instance_variable_set(:@unscoped_object_to_model, model_proc)
        end

        def model_type(graph_type, model_type)
          model_type = model_type.to_s.classify.constantize unless model_type.is_a?(Class)

          object_to_model = -> (object) do
            model_proc = graph_type.instance_variable_get(:@unscoped_object_to_model)
            if model_proc
              model_proc.call(object)
            else
              DEFAULT_OBJECT_TO_MODEL.call(object)
            end
          end

          graph_type.instance_variable_set(:@unscoped_model_type, model_type)

          graph_type.fields['id'] = GraphQL::Field.define do
            name 'id'
            type !types.ID
            resolve -> (object, args, context) { object.gid }
          end

          if GraphQL::Models.node_interface_proc
            node_interface = GraphQL::Models.node_interface_proc.call
            graph_type.interfaces = [*graph_type.interfaces, node_interface].uniq
          end

          graph_type.fields['rid'] = GraphQL::Field.define do
            name 'rid'
            type !types.String
            resolve -> (object, args, context) do
              model = object_to_model.call(object)
              model.id
            end
          end

          graph_type.fields['rtype'] = GraphQL::Field.define do
            name 'rtype'
            type !types.String
            resolve -> (object, args, context) do
              model = object_to_model.call(object)
              model.class.name
            end
          end

          if model_type.columns.detect { |c| c.name == 'created_at'}
            DefinitionHelpers.define_attribute(graph_type, model_type, model_type, [], :created_at, object_to_model, {})
          end

          if model_type.columns.detect { |c| c.name == 'updated_at'}
            DefinitionHelpers.define_attribute(graph_type, model_type, model_type, [], :updated_at, object_to_model, {})
          end
        end

        def proxy_to(graph_type, association, &block)
          ensure_has_model_type(graph_type, __method__)
          object_to_model = graph_type.instance_variable_get(:@unscoped_object_to_model) || DEFAULT_OBJECT_TO_MODEL
          DefinitionHelpers.define_proxy(graph_type, resolve_model_type(graph_type), resolve_model_type(graph_type), [], association, object_to_model, &block)
        end

        def attr(graph_type, name, **options)
          ensure_has_model_type(graph_type, __method__)
          object_to_model = graph_type.instance_variable_get(:@unscoped_object_to_model) || DEFAULT_OBJECT_TO_MODEL
          DefinitionHelpers.define_attribute(graph_type, resolve_model_type(graph_type), resolve_model_type(graph_type), [], name, object_to_model, options)
        end

        def has_one(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          object_to_model = graph_type.instance_variable_get(:@unscoped_object_to_model) || DEFAULT_OBJECT_TO_MODEL
          DefinitionHelpers.define_has_one(graph_type, resolve_model_type(graph_type), resolve_model_type(graph_type), [], association, object_to_model, options)
        end

        def has_many_connection(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          object_to_model = graph_type.instance_variable_get(:@unscoped_object_to_model) || DEFAULT_OBJECT_TO_MODEL
          DefinitionHelpers.define_has_many_connection(graph_type, resolve_model_type(graph_type), resolve_model_type(graph_type), [], association, object_to_model, options)
        end

        def has_many_array(graph_type, association, **options)
          ensure_has_model_type(graph_type, __method__)
          object_to_model = graph_type.instance_variable_get(:@unscoped_object_to_model) || DEFAULT_OBJECT_TO_MODEL
          DefinitionHelpers.define_has_many_array(graph_type, resolve_model_type(graph_type), resolve_model_type(graph_type), [], association, object_to_model, options)
        end

        def backed_by_model(graph_type, model_type, &block)
          model_type = model_type.to_s.classify.constantize unless model_type.is_a?(Class)

          backer = GraphQL::Models::BackedByModel.new(graph_type, model_type)
          backer.instance_exec(&block)
        end

        private

        def resolve_model_type(graph_type)
          graph_type.instance_variable_get(:@unscoped_model_type)
        end

        def ensure_has_model_type(graph_type, method)
          fail RuntimeError.new("You must call model_type before using the #{method} method.") unless graph_type.instance_variable_get(:@unscoped_model_type)
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
