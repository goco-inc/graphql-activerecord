# frozen_string_literal: true

module GraphQL
  module Models
    module DefinitionHelpers
      def self.define_proxy(graph_type, base_model_type, model_type, path, association, object_to_model, detect_nulls, &block)
        reflection = model_type.reflect_on_association(association)
        raise ArgumentError, "Association #{association} wasn't found on model #{model_type.name}" unless reflection
        raise ArgumentError, "Cannot proxy to polymorphic association #{association} on model #{model_type.name}" if reflection.polymorphic?
        raise ArgumentError, "Cannot proxy to #{reflection.macro} association #{association} on model #{model_type.name}" unless %i[has_one belongs_to].include?(reflection.macro)

        return unless block_given?

        proxy = BackedByModel.new(
          graph_type,
          reflection.klass,
          base_model_type: base_model_type,
          path: [*path, association],
          object_to_model: object_to_model,
          detect_nulls: detect_nulls && Reflection.is_required(model_type, association)
        )

        proxy.instance_exec(&block)
      end

      def self.resolve_has_one_type(reflection)
        ############################################
        ## Ordinary has_one/belongs_to associations
        ############################################

        if reflection.polymorphic?
          # For polymorphic associations, we look for a validator that limits the types of entities that could be
          # used, and use it to build a union. If we can't find one, raise an error.

          model_type = reflection.active_record
          valid_types = Reflection.possible_values(model_type, reflection.foreign_type)

          if valid_types.blank?
            raise ArgumentError, "Cannot include polymorphic #{reflection.name} association on model #{model_type.name}, because it does not define an inclusion validator on #{reflection.foreign_type}"
          end

          graph_types = valid_types.map { |t| GraphQL::Models.get_graphql_type(t) }.compact

          GraphQL::UnionType.define do
            name "#{model_type.name.demodulize}#{reflection.foreign_type.classify}"
            description "Objects that can be used as #{reflection.foreign_type.titleize.downcase} on #{model_type.name.titleize.downcase}"
            possible_types graph_types
          end
        else
          GraphQL::Models.get_graphql_type!(reflection.klass)
        end
      end

      # Adds a field to the graph type which is resolved by accessing a has_one association on the model. Traverses
      # across has_one associations specified in the path. The resolver returns a promise.
      def self.define_has_one(graph_type, base_model_type, model_type, path, association, object_to_model, options, detect_nulls)
        reflection = model_type.reflect_on_association(association)

        raise ArgumentError, "Association #{association} wasn't found on model #{model_type.name}" unless reflection
        raise ArgumentError, "Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_one" unless %i[has_one belongs_to].include?(reflection.macro)

        # Define the field for the association itself

        camel_name = options[:name]
        association_graphql_type = resolve_has_one_type(reflection)
        association_graphql_type = resolve_nullability(association_graphql_type, model_type, association, detect_nulls, options)

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_one,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model,
        })

        graph_type.fields[camel_name.to_s] = GraphQL::Field.define do
          name camel_name.to_s
          type association_graphql_type
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, context) do
            return nil unless model
            DefinitionHelpers.load_and_traverse(model, [association], context)
          end
        end

        # Define the field for the associated model's ID
        id_field_name = :"#{camel_name}Id"
        id_field_type = resolve_nullability(GraphQL::ID_TYPE, model_type, association, detect_nulls, options)

        DefinitionHelpers.register_field_metadata(graph_type, id_field_name, {
          macro: :has_one,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model,
        })

        can_use_optimized = reflection.macro == :belongs_to

        if !reflection.polymorphic? && reflection.klass.column_names.include?('type')
          can_use_optimized = false
        end

        graph_type.fields[id_field_name.to_s] = GraphQL::Field.define do
          name id_field_name.to_s
          type id_field_type
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, context) do
            return nil unless model

            if can_use_optimized
              id = model.public_send(reflection.foreign_key)
              return nil if id.nil?

              type = model.association(association).klass.name
              GraphQL::Models.id_for_model.call(type, id)
            else
              # We have to actually load the model and then get it's ID
              DefinitionHelpers.load_and_traverse(model, [association], context).then(&:gid)
            end
          end
        end
      end

      def self.define_has_many_array(graph_type, base_model_type, model_type, path, association, object_to_model, options, detect_nulls)
        reflection = model_type.reflect_on_association(association)

        raise ArgumentError, "Association #{association} wasn't found on model #{model_type.name}" unless reflection
        raise ArgumentError, "Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_array" unless [:has_many].include?(reflection.macro)

        association_type = options[:type] || GraphQL::Models.get_graphql_type!(reflection.klass)

        if !association_type.is_a?(GraphQL::ListType)
          association_type = association_type.to_non_null_type.to_list_type
        end

        id_field_type = GraphQL::ID_TYPE.to_non_null_type.to_list_type

        # The has_many associations are a little special. Instead of checking for a presence validator, we instead assume
        # that the outer type should be non-null, unless detect_nulls is false. In other words, we prefer an empty
        # array for the association, rather than null.
        if (options[:nullable].nil? && detect_nulls) || options[:nullable] == false
          association_type = association_type.to_non_null_type
          id_field_type = id_field_type.to_non_null_type
        end

        camel_name = options[:name]

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_many_array,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model,
        })

        graph_type.fields[camel_name.to_s] = GraphQL::Field.define do
          name camel_name.to_s
          type association_type
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, context) do
            return nil unless model
            DefinitionHelpers.load_and_traverse(model, [association], context).then do |result|
              Array.wrap(result)
            end
          end
        end

        # Define the field for the associated model's ID
        id_field_name = :"#{camel_name.to_s.singularize}Ids"

        DefinitionHelpers.register_field_metadata(graph_type, id_field_name, {
          macro: :has_one,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model,
        })

        graph_type.fields[id_field_name.to_s] = GraphQL::Field.define do
          name id_field_name.to_s
          type id_field_type
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, context) do
            return nil unless model
            DefinitionHelpers.load_and_traverse(model, [association], context).then do |result|
              Array.wrap(result).map(&:gid)
            end
          end
        end
      end

      def self.define_has_many_connection(graph_type, base_model_type, model_type, path, association, object_to_model, options, detect_nulls)
        reflection = model_type.reflect_on_association(association)

        raise ArgumentError, "Association #{association} wasn't found on model #{model_type.name}" unless reflection
        raise ArgumentError, "Cannot include #{reflection.macro} association #{association} on model #{model_type.name} with has_many_connection" unless [:has_many].include?(reflection.macro)

        connection_type = GraphQL::Models.get_graphql_type!(reflection.klass).connection_type

        if (options[:nullable].nil? && detect_nulls) || options[:nullable] == false
          connection_type = connection_type.to_non_null_type
        end

        camel_name = options[:name].to_s

        DefinitionHelpers.register_field_metadata(graph_type, camel_name, {
          macro: :has_many_connection,
          macro_type: :association,
          path: path,
          association: association,
          base_model_type: base_model_type,
          model_type: model_type,
          object_to_base_model: object_to_model,
        })

        connection_field = graph_type.fields[camel_name] = GraphQL::Field.define do
          name(camel_name)
          type(connection_type)
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, _context) do
            return nil unless model
            model.public_send(association)
          end
        end

        connection_field.connection = true
        connection_field
      end
    end
  end
end
