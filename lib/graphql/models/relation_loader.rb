# frozen_string_literal: true

module GraphQL
  module Models
    class RelationLoader < GraphQL::Batch::Loader
      attr_reader :model_class

      def initialize(model_class)
        @model_class = model_class
      end

      def perform(load_requests)
        # Group the requests to load by id into a single relation, and we'll fan it back out after
        # we have the results

        relations = []
        id_requests = load_requests.select { |r| r.load_type == :id }
        id_relation = model_class.where(id: id_requests.map(&:load_target))

        relations.push(id_relation) if id_requests.any?
        relations_to_requests = {}

        # Gather up all of the requests to load a relation, and map the relations back to their requests
        load_requests.select { |r| r.load_type == :relation }.each do |request|
          relation = request.load_target
          relations.push(relation) unless relations.detect { |r| r.object_id == relation.object_id }
          relations_to_requests[relation.object_id] ||= []
          relations_to_requests[relation.object_id].push(request)
        end

        # We need to build a query that will return all of the rows that match any of the relations.
        # But in addition, we also need to know how that relation sorted them. So we pull any ordering
        # information by adding RANK() columns to the query, and we determine whether that row belonged
        # to the query by adding CASE columns.

        # Map each relation to a SQL query that selects only the ID column for the rows that match it
        selection_clauses = relations.map do |relation|
          relation.unscope(:select).select(model_class.primary_key).to_sql
        end

        # Generate a CASE column that will tell us whether the row matches this particular relation
        slicing_columns = relations.each_with_index.map do |_relation, index|
          %{ CASE WHEN "#{model_class.table_name}"."#{model_class.primary_key}" IN (#{selection_clauses[index]}) THEN 1 ELSE 0 END AS "in_relation_#{index}" }
        end

        # For relations that have sorting applied, generate a RANK() column that tells us how the rows are
        # sorted within that relation
        sorting_columns = relations.each_with_index.map do |relation, index|
          arel = relation.arel
          next nil unless arel.orders.any?

          order_by = arel.orders.map do |expr|
            if expr.is_a?(Arel::Nodes::SqlLiteral)
              expr.to_s
            else
              expr.to_sql
            end
          end

          %{ RANK() OVER (ORDER BY #{order_by.join(', ')}) AS "sort_relation_#{index}" }
        end

        sorting_columns.compact!

        # Build the query that will select any of the rows that match the selection clauses
        main_relation = model_class
          .where("id in ((#{selection_clauses.join(") UNION (")}))")
          .select(%( "#{model_class.table_name}".* ))

        main_relation = slicing_columns.reduce(main_relation) { |relation, memo| relation.select(memo) }
        main_relation = sorting_columns.reduce(main_relation) { |relation, memo| relation.select(memo) }

        # Run the query
        result = main_relation.to_a

        # Now multiplex the results out to all of the relations that had asked for values
        relations.each_with_index do |relation, index|
          slice_col = "in_relation_#{index}"
          sort_col = "sort_relation_#{index}"

          matching_rows = result.select { |r| r[slice_col] == 1 }.sort_by { |r| r[sort_col] }

          if relation.object_id == id_relation.object_id
            pk = relation.klass.primary_key

            id_requests.each do |request|
              row = matching_rows.detect { |r| r[pk] == request.load_target }
              fulfill(request, row)
            end
          else
            relations_to_requests[relation.object_id].each do |request|
              fulfill_request(request, matching_rows)
            end
          end
        end
      end

      def fulfill_request(request, result)
        result = request.ensure_cardinality(result)
        request.fulfilled(result)
        fulfill(request, result)
      end
    end
  end
end
