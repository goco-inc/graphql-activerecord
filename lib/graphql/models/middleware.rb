# frozen_string_literal: true
class GraphQL::Models::Middleware
  attr_accessor :skip_nil_models

  def initialize(skip_nil_models = true)
    @skip_nil_models = skip_nil_models
  end

  def call(graphql_type, object, field_definition, args, context)
    # If this field defines a path, load the associations in the path
    field_info = GraphQL::Models.field_info(graphql_type, field_definition.name)
    return yield unless field_info

    # Convert the core object into the model
    base_model = field_info.object_to_base_model.call(object)

    GraphQL::Models.load_association(base_model, field_info.path, context).then do |model|
      next nil if model.nil? && @skip_nil_models

      next_args = [graphql_type, model, field_definition, args, context]
      yield(next_args)
    end
  end
end
