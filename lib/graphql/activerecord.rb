# frozen_string_literal: true

require 'active_support'
require 'active_record'
require 'graphql'
require 'graphql/batch'
require 'graphql/relay'

require 'graphql/models/monkey_patches/graphql_query_context'
require 'graphql/models/active_record_extension'
require 'graphql/models/instrumentation'

# Helpers
require 'graphql/models/helpers'
require 'graphql/models/hash_combiner'
require 'graphql/models/definer'
require 'graphql/models/association_load_request'
require 'graphql/models/attribute_loader'
require 'graphql/models/relation_loader'

# Order matters...
require 'graphql/models/promise_relation_connection'
require 'graphql/models/relation_load_request'
require 'graphql/models/database_types'
require 'graphql/models/reflection'
require 'graphql/models/definition_helpers'
require 'graphql/models/definition_helpers/associations'
require 'graphql/models/definition_helpers/attributes'
require 'graphql/models/mutation_helpers/print_input_fields'
require 'graphql/models/mutation_helpers/apply_changes'
require 'graphql/models/mutation_helpers/authorization'
require 'graphql/models/mutation_helpers/validation_error'
require 'graphql/models/mutation_helpers/validation'
require 'graphql/models/mutation_field_map'

require 'graphql/models/backed_by_model'
require 'graphql/models/mutator'

module GraphQL
  module Models
    class << self
      attr_accessor :model_from_id, :authorize, :id_for_model, :model_to_graphql_type, :unknown_scalar
      attr_accessor :legacy_nulls
    end

    # Returns a promise that will traverse the associations and resolve to the model at the end of the path.
    # You can use this to access associated models inside custom field resolvers, without losing optimization
    # benefits.
    def self.load_association(starting_model, path, context)
      path = Array.wrap(path)
      GraphQL::Models::DefinitionHelpers.load_and_traverse(starting_model, path, context)
    end

    def self.load_relation(relation, fast_query: false)
      if fast_query
        request = AttributeLoader::Request.new(relation.where_values_hash, Helpers.orders_to_sql(relation.orders))
        AttributeLoader.for(relation.klass).load(request)
      else
        request = RelationLoadRequest.new(relation)
        request.load
      end
    end

    def self.field_info(graph_type, field_name)
      field_name = field_name.to_s

      meta = graph_type.instance_variable_get(:@field_metadata)
      return nil unless meta

      meta[field_name]
    end

    def self.authorize!(context, model, action)
      authorize.call(context, model, action)
    end

    def self.define_mutator(definer, model_type, null_behavior: :leave_unchanged, legacy_nulls: GraphQL::Models.legacy_nulls, &block)
      legacy_nulls ||= false

      # HACK: To get the name of the mutation, to avoid possible collisions with other type names
      prefix = definer.instance_variable_get(:@target).name

      mutator_definition = MutatorDefinition.new(model_type, null_behavior: null_behavior, legacy_nulls: legacy_nulls)
      mutator_definition.field_map.instance_exec(&block)
      MutationHelpers.print_input_fields(mutator_definition.field_map, definer, "#{prefix}Input")
      mutator_definition
    end

    def self.get_graphql_type(model_class)
      model_class = model_class.constantize if model_class.is_a?(String)

      if model_to_graphql_type
        model_to_graphql_type[model_class]
      else
        "#{model_class.name}Type".safe_constantize
      end
    end

    def self.get_graphql_type!(model_class)
      type = get_graphql_type(model_class)
      raise "Could not locate GraphQL type for model #{model_class}" if type.nil?
      type
    end
  end
end

GraphQL::ObjectType.accepts_definitions(
  backed_by_model: -> (graph_type, model_type, &block) do
    model_type = model_type.to_s.classify.constantize unless model_type.is_a?(Class)

    backer = GraphQL::Models::BackedByModel.new(graph_type, model_type)
    backer.instance_exec(&block)
  end
)
