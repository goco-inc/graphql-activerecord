# frozen_string_literal: true

module GraphQL
  module Models
    class PromiseRelationConnection < GraphQL::Relay::RelationConnection
      def edges
        # Can't do any optimization if the request is asking for the last X items, since there's
        # no easy way to turn it into a generalized query.
        return super if last

        relation = sliced_nodes
        limit = [first, last, max_page_size].compact.min
        relation = relation.limit(limit) if first
        request = RelationLoadRequest.new(relation)

        request.load.then do |models|
          models.map { |m| GraphQL::Relay::Edge.new(m, self) }
        end
      end
    end

    # GraphQL::Relay::BaseConnection.register_connection_implementation(ActiveRecord::Relation, PromiseRelationConnection)
  end
end
