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

      def eager_fulfill
        return unless context

        yield association.target and return if association.loaded?

        if reflection.macro == :belongs_to
          id = base_model.send(reflection.foreign_key)

          yield nil and return if id.nil?
          yield model_cache[id] and return if model_cache.include?(id)

        elsif reflection.macro == :has_one

          model = model_cache.values.detect do |m|
            m.send(reflection.foreign_key) == base_model.id && (!reflection.options.include?[:as] || m.send(reflection.type) == base_model.class.name)
          end

          yield model and return unless model.nil?
        end
      end


      def in_clause_type
        case reflection.macro
        when :belongs_to
          :id
        else
          :query
        end
      end

      # The resulting query will be something like "where id in (...)". This method needs to return the contents
      # of that 'in' clause.
      def in_clause
        case reflection.macro
        when :belongs_to
          base_model.send(reflection.foreign_key)
        else
          condition = { reflection.foreign_key => base_model.id }

          if reflection.options.include?(:as)
            condition[reflection.type] = base_model.class.name
          end

          target_class.where(condition).select(:id).to_sql
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
            model_cache[m.id] = m if model_cache
          end
        else
          association.target = result
          association.set_inverse_instance(result)
          model_cache[result.id] = result if model_cache
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

      def model_cache
        return nil unless context
        context.model_cache[target_class] ||= {}
      end

    end
  end
end
