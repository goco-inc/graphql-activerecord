module GraphQL::Models
  module MutationHelpers
    def self.authorize_changes(context, all_changes)
      changed_models = all_changes.group_by { |c| c[:model_instance] }

      changed_models.each do |model, changes|
        changes.map { |c| c[:action] }.uniq.each do |action|
          GraphQL::Models.authorize!(context, cm, action)
        end
      end
    end
  end
end
