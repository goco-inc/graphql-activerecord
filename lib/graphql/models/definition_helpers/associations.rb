module GraphQL
  module Models
    module DefinitionHelpers
      def self.define_proxy(graph_type, base_model_type, model_type, path, association, object_to_model, &block)
        reflection = model_type.reflect_on_association(association)
        raise ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        raise ArgumentError.new("Cannot proxy to polymorphic association #{association} on model #{model_type.name}") if reflection.polymorphic?
        raise ArgumentError.new("Cannot proxy to #{reflection.macro} association #{association} on model #{model_type.name}") unless [:has_one, :belongs_to].include?(reflection.macro)

        return unless block_given?

        proxy = ProxyBlock.new(graph_type, base_model_type, reflection.klass, [*path, association], object_to_model)
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
          fail ArgumentError.new("Cannot include polymorphic #{reflection.name} association on model #{model_type.name}, because it does not define an inclusion validator on #{reflection.foreign_type}")
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

      # Adds a field to the graph type which is resolved by accessing a has_one association on the model. Traverses
      # across has_one associations specified in the path. The resolver returns a promise.
      def self.define_has_one(graph_type, base_model_type, model_type, path, association, object_to_model, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_one") unless [:has_one, :belongs_to].include?(reflection.macro)

        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym
        type_lambda = resolve_has_one_type(reflection)

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_one,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model
        })

        graph_type.fields[camel_name.to_s] = GraphQL::Field.define do
          name camel_name.to_s
          type type_lambda
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, args, context) do
            return nil unless model
            DefinitionHelpers.load_and_traverse(model, [association], context)
          end
        end
      end

      def self.define_has_many_array(graph_type, base_model_type, model_type, path, association, object_to_model, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_array") unless [:has_many].include?(reflection.macro)

        type_lambda = options[:type] || -> { types[!"#{reflection.klass.name}Graph".constantize] }
        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_many_array,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model
        })

        graph_type.fields[camel_name.to_s] = GraphQL::Field.define do
          name camel_name.to_s
          type type_lambda
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, args, context) do
            return nil unless model
            DefinitionHelpers.load_and_traverse(model, [association], context).then do |result|
              Array.wrap(result)
            end
          end
        end
      end

      def self.define_has_many_connection(graph_type, base_model_type, model_type, path, association, object_to_model, options)
        reflection = model_type.reflect_on_association(association)

        fail ArgumentError.new("Association #{association} wasn't found on model #{model_type.name}") unless reflection
        fail ArgumentError.new("Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_connection") unless [:has_many].include?(reflection.macro)

        type_lambda = -> { "#{reflection.klass.name}Graph".constantize.connection_type }
        camel_name = options[:name] || association.to_s.camelize(:lower).to_sym

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_many_connection,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model
        })

        GraphQL::Relay::Define::AssignConnection.call(graph_type, camel_name, type_lambda) do
          resolve -> (model, args, context) do
            return nil unless model
            return GraphSupport.secure(model.public_send(association), context)
          end
        end
      end
    end
  end
end
