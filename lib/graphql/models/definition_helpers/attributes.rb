module GraphQL
  module Models
    module DefinitionHelpers
      def self.type_to_graphql_type(type)
        case type
        when :boolean
          types.Boolean
        when :integer
          types.Int
        when :float
          types.Float
        when :daterange, :tsrange
          types[!types.String]
        else
          resolved = ScalarTypes.registered_type(type) || types.String
          resolved.is_a?(Proc) ? resolved.call : resolved
        end
      end

      def self.get_column(model_type, name)
        col = model_type.columns.detect { |c| c.name == name.to_s }
        raise ArgumentError.new("The attribute #{name} wasn't found on model #{model_type.name}.") unless col

        if model_type.graphql_enum_types.include?(name)
          graphql_type = model_type.graphql_enum_types[name]
        else
          graphql_type = type_to_graphql_type(col.type)
        end

        if col.array
          graphql_type = types[graphql_type]
        end

        return OpenStruct.new({
          is_range: /range\z/ === col.type.to_s,
          camel_name: name.to_s.camelize(:lower).to_sym,
          graphql_type: graphql_type
        })
      end

      def self.range_to_graphql(value)
        return nil unless value

        begin
          [value.first, value.last_included]
        rescue TypeError
          [value.first, value.last]
        end
      end

      def self.define_attribute(definer, model_type, path, attribute, options)
        column = get_column(model_type, attribute)

        field_name = options[:name] || column.camel_name

        DefinitionHelpers.register_field_metadata(definer.resolved_model_type, field_name, {
          macro: :attr,
          macro_type: :attribute,
          type_proc: -> { column.graphql_type },
          path: path,
          attribute: attribute,
          options: options
        })

        definer.field field_name, column.graphql_type do
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (base_model, args, context) do
            DefinitionHelpers.load_and_traverse(base_model, path, context).then do |model|
              next nil unless model
              # next nil unless context.can?(:read, model)

              if column.is_range
                DefinitionHelpers.range_to_graphql(model.public_send(attribute))
              else
                if model_type.graphql_resolvers.include?(attribute)
                  resolve_proc = model_type.graphql_resolvers[attribute]
                  model.instance_exec(&resolve_proc)
                else
                  model.public_send(attribute)
                end
              end
            end
          end
        end
      end
    end
  end
end
