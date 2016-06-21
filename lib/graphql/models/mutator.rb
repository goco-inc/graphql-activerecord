module GraphQL::Models
  class Mutator
    attr_accessor :field_map, :root_model, :inputs, :context

    def initialize(field_map, root_model, inputs, context)
      @field_map = field_map
      @root_model = root_model
      @inputs = inputs
      @context = context
    end

    def apply_changes
      fail StandardError.new("Called apply_changes twice for the same mutator") if @all_changes
      @all_changes = MutationHelpers.apply_changes(field_map, root_model, inputs, context)
      changed_models
    end

    def changed_models
      fail StandardError.new("Need to call apply_changes before #{__method__}") unless @all_changes
      @all_changes.map { |c| c[:model_instance] }.uniq
    end

    def validate!
      fail StandardError.new("Need to call apply_changes before #{__method__}") unless @all_changes
      MutationHelpers.validate_changes(inputs, field_map, root_model, context, @all_changes)
    end

    def authorize!
      fail StandardError.new("Need to call apply_changes before #{__method__}") unless @all_changes
      MutationHelpers.authorize_changes(context, @all_changes)
    end

    def save!
      fail StandardError.new("Need to call apply_changes before #{__method__}") unless @all_changes

      ActiveRecord::Base.transaction(requires_new: true) do
        changed_models.each do |model|
          next if model.destroyed?

          if model.marked_for_destruction?
            model.destroy
          else
            model.save!
          end
        end

        changed_models.reject(&:destroyed?).each(&:reload)
      end
    end
  end

  class MutatorDefinition
    attr_accessor :field_map

    def initialize(model_type, null_behavior:)
      @field_map = MutationFieldMap.new(model_type, find_by: nil, null_behavior: null_behavior)
    end

    def mutator(root_model, inputs, context)
      Mutator.new(field_map, root_model, inputs, context)
    end
  end
end
