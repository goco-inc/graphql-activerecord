# frozen_string_literal: true

class GraphQL::Models::Instrumentation
  # @param skip_nil_models If true, field resolvers (in proxy_to or backed_by_model blocks) will not be invoked if the model is nil.
  def initialize(skip_nil_models = true)
    @skip_nil_models = skip_nil_models
  end

  def instrument(type, field)
    field_info = GraphQL::Models.field_info(type, field.name)
    return field unless field_info

    old_resolver = field.resolve_proc

    new_resolver = -> (object, args, ctx) {
      Promise.resolve(field_info.object_to_base_model.call(object)).then do |base_model|
        GraphQL::Models.load_association(base_model, field_info.path, ctx).then do |model|
          next nil if model.nil? && @skip_nil_models
          old_resolver.call(model, args, ctx)
        end
      end
    }

    field.redefine do
      resolve(new_resolver)
    end
  end
end
