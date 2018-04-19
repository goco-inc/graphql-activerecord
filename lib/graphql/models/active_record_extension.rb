# frozen_string_literal: true

module GraphQL
  module Models
    module ActiveRecordExtension
      class EnumTypeHash
        extend Forwardable

        attr_accessor :hash

        def initialize
          @hash = {}.with_indifferent_access
        end

        def [](attribute)
          type = hash[attribute]
          type = type.call if type.is_a?(Proc)
          type = type.constantize if type.is_a?(String)
          type
        end

        def_delegators :@hash, :[]=, :include?, :keys
      end

      extend ::ActiveSupport::Concern
      class_methods do
        def graphql_enum_types
          @graphql_enum_types ||= EnumTypeHash.new
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

          values = if defined_enums.include?(attribute.to_s)
            defined_enums[attribute.to_s].keys
          else
            Reflection.possible_values(self, attribute)
          end

          if values.nil?
            raise ArgumentError, "Could not auto-detect the values for enum #{attribute} on #{self.name}"
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

::ActiveRecord::Base.send(:include, GraphQL::Models::ActiveRecordExtension)
