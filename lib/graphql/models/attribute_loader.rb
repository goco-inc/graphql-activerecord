# frozen_string_literal: true

module GraphQL::Models
  # Simplified loader that can take a hash of attributes to match, combine them into a single query, and then fulfill
  # then individually. It can also ask the database to order them correctly.
  class AttributeLoader < GraphQL::Batch::Loader
    attr_reader :model_class

    def initialize(model_class)
      @model_class = model_class
    end

    class Request
      attr_accessor :attributes, :sorting
      def initialize(attributes, sorting)
        @attributes = attributes
        @sorting = sorting
      end
    end

    WHERE_STRIP = /\AWHERE /

    # @param requests An AttributeLoader::Request (or a simple hash) that describes the models to be loaded
    def perform(requests)
      # Combine the conditions together, into the minimal set of conditions needed
      conditions = HashCombiner.combine(requests.map { |r| r.is_a?(Request) ? r.attributes : r })

      # Get the distinct list of sorting conditions that we need to ask for, also
      sorters = requests.map { |r| r.is_a?(Request) ? r.sorting : nil }.compact.reject(&:blank?).uniq

      # Start constructing the query that we'll execute to get the results
      table = model_class.arel_table

      # Start building the query, add in the where conditions
      conditions.map! { |cond| hash_to_condition(table, cond) }
      query = table.where(conditions.reduce { |memo, cond| memo.or(cond) })

      # Convert the list of sorters into RANK() selections that we'll add to the selection
      order_selections = sorters.each_with_index.map { |s, idx| order_selection(s, idx) }

      # Add the projections to the query
      query = order_selections.reduce(query.project(:*)) { |memo, selection| memo.project(selection) }

      # Get the result set
      results = model_class.find_by_sql(query.to_sql)

      # De-multiplex the result set and fulfill the requests
      requests.each do |request|
        # Get the rows that match this request
        response = match_results(results, request)

        if response.size > 1 && request.is_a?(Request) && request.sorting
          idx = sorters.index(request.sorting)
          sort_by = "rank_#{idx}"
          response = response.sort_by { |row| row[sort_by] }
        end

        fulfill(request, response)
      end
    end

    private

    def order_selection(sorter, idx)
      arel = model_class.unscoped.order(sorter).arel
      order_sql = Helpers.orders_to_sql(arel.orders)
      %{ DENSE_RANK() OVER(ORDER BY #{order_sql}) AS rank_#{idx} }
    end

    # Converts a hash into arel conditions
    def hash_to_condition(table, hash)
      conditions = hash.map do |attr, value|
        if value.is_a?(Array) && value.size > 1
          table[attr].in(value)
        elsif value.is_a?(Array)
          table[attr].eq(value[0])
        else
          table[attr].eq(value)
        end
      end

      conditions.reduce { |memo, cond| memo.and(cond) }
    end

    def match_results(results, request)
      # Find all of the items in the results that match the request
      attributes = request.is_a?(Request) ? request.attributes : request

      results.select do |row|
        attributes.all? { |key, value| is_match(row.send(key), value) }
      end
    end

    def is_match(row_value, compare_value)
      compare_value.is_a?(Array) ? compare_value.include?(row_value) : compare_value == row_value
    end
  end
end
