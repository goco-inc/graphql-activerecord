module GraphQL
  module Models
    class Loader < GraphQL::Batch::Loader
      attr_reader :model_class

      def initialize(model_class)
        @model_class = model_class
      end

      def perform(load_requests)
        # Each load request should return a SQL query that returns a list of ID's for the models
        # that the request is asking to have loaded.

        # If the request can be eager fulfilled, exclude it from the result
        load_requests.each do |request|
          request.eager_fulfill { |result| fulfill_request(request, model) }
        end

        load_requests = load_requests.reject { |r| fulfilled?(r) }
        return if load_requests.empty?

        grouped = load_requests.group_by(&:in_clause_type)

        id_requests = grouped[:id] || []
        query_requests = grouped[:query] || []

        queries = query_requests.map { |r| model_class.where("#{model_class.table_name}.id in (#{r.in_clause})").select(:id).to_sql }

        # We want to build a query that will return all of the models that match any of the queries,
        # and we want the server to also tell us which ones matched that particular query
        extra_columns = query_requests.each_with_index.map do |request, index|
          "CASE WHEN #{model_class.table_name}.id IN (#{request.in_clause}) THEN true ELSE false END AS load_req_#{index}"
        end

        conditions = []
        if id_requests.any?
          first = id_requests[0].in_clause
          id_values = id_requests.map { |r| ActiveRecord::Base.sanitize(r.in_clause) }.join(', ')
          conditions.push("#{model_class.table_name}.id in (#{id_values})")
        end

        if queries.any?
          union = queries.join(' UNION ')
          conditions.push("#{model_class.table_name}.id in (#{union})")
        end

        result = @model_class.where(conditions.join(" OR ")).select(["#{model_class.table_name}.*", *extra_columns].join(', '))

        id_requests.each do |req|
          model = result.detect { |m| m.id == req.in_clause }
          fulfill_request(req, model)
        end

        query_requests.each_with_index do |req, idx|
          loaded_column = "load_req_#{idx}"
          models = result.select { |m| m[loaded_column] }
          fulfill_request(req, models)
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
