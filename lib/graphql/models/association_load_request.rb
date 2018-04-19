# frozen_string_literal: true

module GraphQL
  module Models
    class AssociationLoadRequest
      attr_reader :base_model, :association, :context

      def initialize(base_model, association_name, context)
        @base_model = base_model
        @association = base_model.association(association_name)
        @context = context

        if reflection.is_a?(ActiveRecord::Reflection::ThroughReflection)
          raise ArgumentError, "You cannot batch-load a has_many :through association. Instead, load each association individually."
        end
      end

      def request
        AttributeLoader::Request.new(
          association.scope.where_values_hash,
          Helpers.orders_to_sql(association.scope.orders)
        )
      end

      def load
        loader.load(request).then do |result|
          result = result.first unless reflection.macro == :has_many
          Helpers.load_association_with(association, result)
          result
        end
      end

      #################################################################
      # Public members specific to an association load request
      #################################################################

      def target_class
        if reflection.polymorphic?
          base_model.send(reflection.foreign_type).constantize
        else
          reflection.klass
        end
      end

      private

      def loader
        @loader ||= AttributeLoader.for(target_class)
      end

      def reflection
        association.reflection
      end
    end
  end
end
