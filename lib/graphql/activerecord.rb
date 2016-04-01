require 'graphql'

require 'graphql/models/monkey_patches/graphql_query_context'
require 'graphql/models/active_record_extension'

# Helpers
require 'graphql/models/definer'
require 'graphql/models/association_load_request'
require 'graphql/models/loader'

# Order matters...
require 'graphql/models/promise_relation_connection'
require 'graphql/models/relation_load_request'
require 'graphql/models/identification'
require 'graphql/models/proxy_block'
require 'graphql/models/scalar_types'
require 'graphql/models/definition_helpers'
require 'graphql/models/definition_helpers/associations'
require 'graphql/models/definition_helpers/attributes'
require 'graphql/models/object_type'

module GraphQL
  module Models
    class << self
      attr_accessor :node_interface_proc
    end

    # Returns a promise that will traverse the associations and resolve to the model at the end of the path.
    # You can use this to access associated models inside custom field resolvers, without losing optimization
    # benefits.
    def self.load_association(starting_model, path, context)
      path = Array.wrap(path)
      GraphQL::Models::DefinitionHelpers.load_and_traverse(starting_model, path, context)
    end

    def self.load_relation(relation)
      request = RelationLoadRequest.new(relation)
      request.load
    end

    def self.field_info(graph_type, field_name)
      field_name = field_name.to_s

      meta = graph_type.instance_variable_get(:@field_metadata)
      return nil unless meta
      
      meta[field_name]
    end

    def self.register_computed_type(&block)
      GraphQL::Models::Identification.register_computed_type(&block)
    end
  end
end
