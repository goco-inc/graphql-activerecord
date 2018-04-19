# frozen_string_literal: true

module GraphQL
  module Models
    class RelationLoadRequest
      attr_reader :relation

      def initialize(relation)
        @relation = relation
      end

      ####################################################################
      # Public members that all load requests should implement
      ####################################################################

      def load_type
        :relation
      end

      def load_target
        relation
      end

      # If the value should be an array, make sure it's an array. If it should be a single value, make sure it's single.
      # Passed in result could be a single model or an array of models.
      def ensure_cardinality(result)
        Array.wrap(result)
      end

      # When the request is fulfilled, this method is called so that it can do whatever caching, etc. is needed
      def fulfilled(result); end

      def load
        loader.load(self)
      end

      #################################################################
      # Public members specific to a relation load request
      #################################################################

      def target_class
        relation.klass
      end

      private

      def loader
        @loader ||= RelationLoader.for(target_class)
      end
    end
  end
end
