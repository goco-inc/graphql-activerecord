# frozen_string_literal: true

module GraphQL
  module Models
    module DefinitionHelpers
      def self.resolve_nullability(graphql_type, model_class, attribute_or_association, detect_nulls, options)
        # If detect_nulls is true, it means that everything on the path (ie, between base_model_class and model_class) is non null.
        # So for example, if we're five levels deep inside of proxy_to blocks, but every single association along the way has
        # a presence validator, then `detect_nulls` is false. Thus, we can take it one step further and enforce nullability on the
        # attribute itself.
        nullable = options[:nullable]

        if nullable.nil?
          nullable = !(detect_nulls && Reflection.is_required(model_class, attribute_or_association))
        end

        if nullable == false
          graphql_type = graphql_type.to_non_null_type
        else
          graphql_type
        end
      end

      def self.define_attribute(graph_type, base_model_class, model_class, path, attribute, object_to_model, options, detect_nulls, &block)
        attribute_graphql_type = Reflection.attribute_graphql_type(model_class, attribute).output
        attribute_graphql_type = resolve_nullability(attribute_graphql_type, model_class, attribute, detect_nulls, options)

        field_name = options[:name]

        DefinitionHelpers.register_field_metadata(graph_type, field_name, {
          macro: :attr,
          macro_type: :attribute,
          path: path,
          attribute: attribute,
          base_model_class: base_model_class,
          model_class: model_class,
          object_to_base_model: object_to_model,
        })

        graph_type.fields[field_name.to_s] = GraphQL::Field.define do
          name field_name.to_s
          type attribute_graphql_type
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (model, _args, _context) do
            model&.public_send(attribute)
          end

          instance_exec(&block) if block
        end
      end
    end
  end
end
