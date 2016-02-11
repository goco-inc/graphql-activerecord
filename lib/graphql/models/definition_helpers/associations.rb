module GraphQL
  module Models
    module DefinitionHelpers
      def self.define_proxy(definer, model_type, path, association, &block)
        reflection = model_type.reflect_on_association(association)
        raise ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        raise ArgumentError.new("Cannot proxy to polymorphic association #{association} on model #{model_type.name}") if reflection.polymorphic?
        raise ArgumentError.new("Cannot proxy to #{reflection.macro} association #{association} on model #{model_type.name}") unless [:has_one, :belongs_to].include?(reflection.macro)

        return unless block_given?

        proxy = ProxyBlock.new(definer, reflection.klass, [*path, association])
        proxy.instance_exec(&block)
      end

      def self.resolve_has_one_type(reflection)
        ############################################
        ## Ordinary has_one/belongs_to associations
        ############################################

        return -> { "#{reflection.klass.name}Graph".constantize } if !reflection.polymorphic?

        ############################################
        ## Polymorphic associations
        ############################################

        # For polymorphic associations, we look for a validator that limits the types of entities that could be
        # used, and use it to build a union. If we can't find one, raise an error.

        model_type = reflection.active_record
        valid_types = detect_inclusion_values(model_type, reflection.foreign_type)

        if valid_types.blank?
          fail ArgumentError.new("Cannot include polymorphic #{reflection.name} association on model #{model_type.name}, because it does not define an inclusion validator on #{refleciton.foreign_type}")
        end

        return ->() do
          graph_types = valid_types.map { |t| "#{t}Graph".safe_constantize }.compact

          GraphQL::UnionType.define do
            name "#{model_type.name}#{reflection.foreign_type.classify}"
            description "Objects that can be used as #{reflection.foreign_type.titleize.downcase} on #{model_type.name.titleize.downcase}"
            possible_types graph_types
          end
        end
      end

      def self.define_has_one(definer, model_type, path, association, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_one") unless [:has_one, :belongs_to].include?(reflection.macro)

        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym

        definer.field camel_name, resolve_has_one_type(reflection) do
          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)
            return nil unless model

            value = model.public_send(association)
            return nil unless context.can?(:read, value)
            return value
          end
        end
      end

      def self.define_has_many_array(definer, model_type, path, association, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_array") unless [:has_many].include?(reflection.macro)

        type_lambda = -> { types["#{reflection.klass.name}Graph".constantize] }
        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym

        definer.field camel_name, type_lambda do
          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)
            return nil unless model
            return GraphSupport.secure(model.public_send(association), context)
          end
        end
      end

      def self.define_has_many_connection(definer, model_type, path, association, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_connection") unless [:has_many].include?(reflection.macro)

        type_lambda = -> { "#{reflection.klass.name}Graph".constantize.connection_type }
        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym

        definer.connection camel_name, type_lambda do
          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)
            return nil unless model
            return GraphSupport.secure(model.public_send(association), context)
          end
        end
      end
    end
  end
end
