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
      sorters = requests.map { |r| r.is_a?(Request) ? r.sorting : nil }.compact

      # Convert the list of conditions into SQL statements, so that we can them combine them using OR
      where_sqls = conditions.map { |c| where_sql(c) }

      # Convert the list of sorters into RANK() selections that we'll add to the selection
      order_selections = sorters.each_with_index.map { |s, idx| order_selection(s, idx) }

      # Get the result set
      results = model_class.unscoped.where(where_sqls.join(' OR '))

      # De-multiplex the result set, and sort them as requested, and return the results
      
    end

    private

    def order_selection(sorter, idx)
      arel = model_class.unscoped.order(sorter).arel
      expressions = arel.orders.map do |expr|
        case expr
        when Arel::Nodes::SqlLiteral
          expr.to_s
        else
          expr.to_sql
        end
      end

      %{ DENSE_RANK() OVER(ORDER BY #{expressions.join(', ')}) AS rank_#{idx} }
    end

    def where_sql(conditions)
      sql = model_class.unscoped.where(conditions).where_sql.sub(WHERE_STRIP, '')
      "(#{sql})"
    end
  end
end
