module GraphQL::Models::Middleware
  def self.call(graphql_type, object, field_definition, args, context, next_middleware)
    # If this field defines a path, load the associations in the path
    field_info = GraphQL::Models.field_info(graphql_type, field_definition.name)
    return next_middleware.call unless field_info

    # Convert the core object into the model
    base_model = field_info.object_to_base_model.call(object)

    GraphQL::Models.load_association(base_model, field_info.path, context).then do |model|
      next_args = [graphql_type, model, field_definition, args, context]
      next_middleware.call(next_args)
    end
  end
end
