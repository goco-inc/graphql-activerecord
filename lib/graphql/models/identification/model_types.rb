module GraphQL
  module Models
    module Identification
      def self.is_model_type(name)
        /\A[a-zA-Z0-9]+\z/ === name && name == name.classify && ActiveRecord::Base.connection.table_exists?(name.tableize)
      end

      def self.resolve_model_type(name, id, context)
        model_class = name.classify.constantize
        result = model_class.where(id: id)
        result = result.accessible_by(context.ability) if context.ability

        result.first
      end
    end
  end
end
