module GraphQL
  module Models
    class ModelType < GraphQL::ObjectType
      attr_accessor :model_type
      defined_by_config :model_type, *GraphQL::ObjectType.instance_variable_get(:@defined_attrs)

      def self.define(&block)
        config = ModelTypeConfig.new
        block && config.instance_eval(&block)
        config.to_instance(self.new, @defined_attrs)
      end
    end
  end
end
