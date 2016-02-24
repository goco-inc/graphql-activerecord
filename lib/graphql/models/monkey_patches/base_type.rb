module GraphQL::BaseType::HasPossibleTypes
  # This monkey patch makes it easier to work with union and interface types
  remove_const('DEFAULT_RESOLVE_TYPE')

  DEFAULT_RESOLVE_TYPE = -> (object) do
    GraphQL::Models::NodeIdentification.type_from_object(object)
  end
end
