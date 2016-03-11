# This is only a temporary monkey patch...
class GraphQL::Relay::ConnectionField
  class << self
    def get_connection_resolve(field_name, underlying_resolve, max_page_size: nil)
      -> (obj, args, ctx) {
         items = underlying_resolve.call(obj, args, ctx)

         # In the original version of this method, the following line was:
         # if items == GraphQL::Query::DEFAULT_RESOLVE
         # The problme is that if items.is_a?(ActiveRecord::Relation), this uses the relation's equality checker,
         # and that equality check will load the relation.

         if GraphQL::Query::DEFAULT_RESOLVE == items
           items = obj.public_send(field_name)
         end

         connection_class = GraphQL::Relay::BaseConnection.connection_for_items(items)
         connection_class.new(items, args, max_page_size: max_page_size)
       }
    end
  end
end
