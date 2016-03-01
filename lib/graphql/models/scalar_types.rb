module GraphQL
  module Models
    module ScalarTypes
      def self.registered_type(database_type)
        @registered_types ||= {}.with_indifferent_access
        @registered_types[database_type]
      end

      def self.register(database_type, graphql_type)
        @registered_types ||= {}.with_indifferent_access
        @registered_types[database_type] = graphql_type
      end
    end
  end
end
