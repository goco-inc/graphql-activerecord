module GraphQL
  module Models
    class AssociationLoadRequest
      attr_reader :base_model, :association, :context

      def initialize(base_model, association_name, context)
        @base_model = base_model
        @association = base_model.association(association_name)
        @context = context
      end

      ####################################################################
      # Public members that all load requests should implement
      ####################################################################

      def load_type
        case reflection.macro
        when :belongs_to
          :id
        else
          :relation
        end
      end
      
      def load_target
        case reflection.macro
        when :belongs_to
          base_model.send(reflection.foreign_key)
        when :has_many
          base_model.send(association.reflection.name)
        else
          # has_one, need to construct our own relation, because accessing the relation will load the model
          condition = { reflection.foreign_key => base_model.id }

          if reflection.options.include?(:as)
            condition[reflection.type] = base_model.class.name
          end

          target_class.where(condition)
        end
      end

      # If the value should be an array, make sure it's an array. If it should be a single value, make sure it's single.
      # Passed in result could be a single model or an array of models.
      def ensure_cardinality(result)
        case reflection.macro
        when :has_many
          Array.wrap(result)
        else
          result.is_a?(Array) ? result[0] : result
        end
      end

      # When the request is fulfilled, this method is called so that it can do whatever caching, etc. is needed
      def fulfilled(result)
        association.loaded!

        if reflection.macro == :has_many
          association.target.concat(result)
          result.each do |m|
            association.set_inverse_instance(m)
          end
        else
          association.target = result
          association.set_inverse_instance(result)
        end
      end

      #################################################################
      # Public members specific to an association load request
      #################################################################

      def target_class
        case when reflection.polymorphic?
          base_model.send(reflection.foreign_type).constantize
        else
          reflection.klass
        end
      end

      private

      def reflection
        association.reflection
      end

    end
  end
end
