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

        if model_type.respond_to?(:defined_enums) && model_type.defined_enums.include?(name.to_s)
          graphql_type = get_enum_type(model_type, name)
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

      def self.get_enum_type(model_type, name)
        enum_type = model_type.graphql_enum_types[name]

        unless enum_type
          warn "[DEPRECATED] Automatically defined enums on models is deprecated. Call `graphql_enum :#{name}` explicitly on #{model_type.name} instead."
          enum_type = model_type.graphql_enum(name, { upcase: false })
        end

        enum_type
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

        definer.noauth_field field_name, column.graphql_type do
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)

            return nil unless model
            context.authorize!(:read, model)

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
