module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::DefinitionHelpers::TypeDefiner.instance
      end

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
          types.String
        end
      end

      def self.get_column(model_type, name)
        col = model_type.columns.detect { |c| c.name == name.to_s }
        raise ArgumentError.new("The attribute #{name} wasn't found on model #{model_type.name}.") unless col

        if model_type.respond_to?(:defined_enums) && model_type.defined_enums.include?(name.to_s)
          graphql_type = GraphQL::EnumType.define do
            name "#{model_type.name}#{name.to_s.classify}"
            description "#{name.to_s.titleize} field on #{model_type.name.titleize}"

            model_type.defined_enums[name.to_s].keys.each do |enum_val|
              value(enum_val, enum_val.titleize)
            end
          end
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

      def self.traverse_path(base_model, path, context)
        model = base_model
        path.each do |segment|
          return nil unless model
          model = model.public_send(segment)
        end

        return model
      end

      # Detects the values that are valid for an attribute by looking at the inclusion validators
      def self.detect_inclusion_values(model_type, attribute)
        # Get all of the inclusion validators
        validators = model_type.validators_on(attribute).select { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }

        # Ignore any inclusion validators that are using the 'if' or 'unless' options
        validators = validators.reject { |v| v.options.include?(:if) || v.options.include?(:unless) || v.options[:in].blank? }
        return nil unless validators.any?
        return validators.map { |v| v.options[:in] }.reduce(:&)
      end

      def self.define_attribute(definer, model_type, path, attribute, options)
        column = get_column(model_type, attribute)

        field_name = options[:name] || column.camel_name

        definer.field field_name, column.graphql_type do
          description options[:description] if options.include?(:description)
          deprecation_reason options[:deprecation_reason] if options.include?(:deprecation_reason)

          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)

            return nil unless model
            return nil unless context.can?(:read, model)

            if column.is_range
              DefinitionHelpers.range_to_graphql(model.public_send(attribute))
            else
              model.public_send(attribute)
            end
          end
        end
      end

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

      def self.define_attachment(definer, model_type, path, attribute, options)
        field_name = options[:name] || attribute.to_s.camelize(:lower).to_sym

        definer.field field_name, -> { AttachmentField } do
          resolve -> (base_model, args, context) do
            model = DefinitionHelpers.traverse_path(base_model, path, context)

            return nil unless model
            return nil unless context.can?(:read, model)

            attachment = model.public_send(attribute)
            return nil if attachment.blank?
            return attachment
          end
        end
      end
    end
  end
end
