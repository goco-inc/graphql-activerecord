module GraphQL
  module Models
    module ActiveRecordExtension
      extend ActiveSupport::Concern
      class_methods do
        def graphql_enum_types
          @_graphql_enum_types ||= {}.with_indifferent_access
        end

        # Defines a GraphQL enum type on the model
        def graphql_enum(attribute, type: nil, upcase: true)
          # Case 1: Providing a type. Only thing to do is register the enum type.
          if type
            graphql_enum_types[attribute] = type
            return type
          end

          # Case 2: Automatically generating the type
          name = "#{self.name}#{attribute.to_s.classify}"
          description = "#{attribute.to_s.titleize} field on #{self.name.titleize}"

          if defined_enums.include?(attribute.to_s)
            values = defined_enums[attribute.to_s].keys
          else
            values = DefinitionHelpers.detect_inclusion_values(self, attribute)
          end

          if values.nil?
            fail ArgumentError.new("Could not auto-detect the values for enum #{attribute} on #{self.name}")
          end

          type = GraphQL::EnumType.define do
            name(name)
            description(description)

            values.each do |val|
              value(upcase ? val.upcase : val, val.to_s.titleize, value: val)
            end
          end

          graphql_enum_types[attribute] = type
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, GraphQL::Models::ActiveRecordExtension)
