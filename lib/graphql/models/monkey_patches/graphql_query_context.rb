# frozen_string_literal: true

class GraphQL::Query::Context
  def cached_models
    @cached_models ||= Set.new
  end
end

class GraphQL::Query::Context::FieldResolutionContext
  def cached_models
    @context.cached_models
  end
end
