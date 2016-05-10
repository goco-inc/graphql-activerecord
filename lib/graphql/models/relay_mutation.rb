module GraphQL::Models
  class RelayMutation
    include GraphQL::Define::InstanceDefinable

    attr_accessor :name, :resolve, :field_maps, :return_fields, :extra_input_fields

    accepts_definitions(
      :name,
      :resolve,

      backed_by_model: -> (instance, model_type, find_by: :id, null_behavior:, &block) do
        fail ArgumentError.new("find_by #{find_by} is not supported") unless find_by == :id

        map = MutationFieldMap.new(model_type, find_by: find_by, null_behavior: null_behavior)
        map.instance_exec(&block)
        instance.field_maps.push(map)
      end,

      return_field: -> (instance, name, type) do
        instance.return_fields[name] = type
      end,

      input_field: -> (instance, *args) do
        instance.extra_input_fields.push(args)
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
          MutationHelpers.print_input_fields(map, self, mutation.name)
        end

        Array.wrap(mutation.extra_input_fields).each do |args|
          input_field(*args)
        end

        mutation.return_fields.each do |name, type|
          return_field(name, type)
        end

        resolve -> (inputs, context) do
          ActiveRecord::Base.transaction(requires_new: true) do
            root_models = mutation.field_maps.map do |map|
              key_field_value = inputs[map.find_by[0]]

              if key_field_value.nil?
                GraphQL::Models.authorize!(context, :create, map.model_type)
                root_model = map.model_type.new
              else
                root_model = GraphQL::Models.model_from_id.call(key_field_value, context)
              end

              unless root_model
                fail GraphQL::ExecutionError.new("Could not find #{map.model_type.name} with id #{key_field_value}")
              end

              # Apply the changes to the models
              all_changes = MutationHelpers.apply_changes(map, root_model, inputs, context)

              if root_model.new_record?
                all_changes.push({ model_instance: root_model, action: :create })
              end

              # Validate the changes
              MutationHelpers.validate_changes(inputs, map, root_model, context, all_changes)

              # Authorize the changes
              MutationHelpers.authorize_changes(context, all_changes)

              # Save the changes
              all_changes.map { |c| c[:model_instance] }.uniq.each(&:save!)

              # Return the result
              root_model.reload
            end

            # Invoke the resolver to get the final return value for the mutation
            mutation.resolve.call(*root_models, inputs, context)
          end
        end
      end
    end
  end
end
