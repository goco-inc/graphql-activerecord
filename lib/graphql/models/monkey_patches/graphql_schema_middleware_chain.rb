# Monkey patch... there will soon be a PR in graphql-ruby for this functionality,
# Talked with the gem author (@rmosolgo) and he said it was a good feature, so likely to land soon
class GraphQL::Schema::MiddlewareChain
  def call(next_arguments = @arguments)
    @arguments = next_arguments
    next_step = steps.shift
    next_middleware = self
    next_step.call(*arguments, next_middleware)
  end
end
