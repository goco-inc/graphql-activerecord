module GraphQL::Models
  class RelayMutation
    include GraphQL::Define::InstanceDefinable

    attr_accessor :name, :authorize, :resolve, :field_maps, :return_fields

    accepts_definitions(
      :name,
      :authorize,
      :resolve,

      backed_by_model: -> (instance, model_type, find_by:, null_behavior:, &block) do
        map = MutationFieldMap.new(model_type, find_by: find_by, null_behavior: null_behavior)
        map.instance_exec(&block)
        instance.field_maps.push(map)
      end,

      return_field: -> (instance, name, type) do
        instance.return_fields[name] = type
      end
    )

    def self.build(&block)
      define(&block).build_relay_mutation
    end

    def initialize
      @field_maps = []
      @return_fields = {}.with_indifferent_access
    end

    def build_relay_mutation
      mutation = self

      GraphQL::Relay::Mutation.define do
        name(mutation.name)

        mutation.field_maps.each do |map|
          GraphQL::Models::MutationHelpers.print_input_fields(map, self, mutation.name)
        end

        mutation.return_fields.each do |name, type|
          return_field(name, type)
        end

        resolve -> (inputs, context) do
          fail NotImplementedError.new
        end
      end
    end
  end
end
