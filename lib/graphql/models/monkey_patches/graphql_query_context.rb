class GraphQL::Query::Context
  def cached_models
    @cached_models ||= Set.new
  end
end
