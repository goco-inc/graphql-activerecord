module GraphQL::BaseType::HasPossibleTypes
  # This monkey patch makes it easier to work with union and interface types
  remove_const('DEFAULT_RESOLVE_TYPE')

  DEFAULT_RESOLVE_TYPE = -> (object) do
    obj_type = GraphQL::Relay::GlobalNodeIdentification.instance.type_from_object(object)
    return obj_type if possible_types.include?(obj_type)
    nil
  end
end
