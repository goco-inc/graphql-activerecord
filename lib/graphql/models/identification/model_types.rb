module GraphQL
  module Models
    module Identification
      def self.is_model_type(name)
        /\A[a-zA-Z0-9]+\z/ === name && name == name.classify && ActiveRecord::Base.connection.table_exists?(name.tableize)
      end

      def self.resolve_model_type(name, id, context)
        model_class = name.classify.constantize
        model_class.find_by(id: id)
      end
    end
  end
end
