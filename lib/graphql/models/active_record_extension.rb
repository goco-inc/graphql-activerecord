module GraphQL
  module Models
    module ActiveRecordExtension
      extend ActiveSupport::Concern

      # Default options for graphql_enums
      ENUM_OPTIONS = {
        upcase: true
      }

      class_methods do
        def graphql_enum_types
          @_graphql_enum_types ||= {}.with_indifferent_access
        end

        # Defines a GraphQL enum type on the model
        def graphql_enum(attribute, **options)
          options = ENUM_OPTIONS.merge(options)
          options[:name] ||= "#{self.name}#{attribute.to_s.classify}"
          options[:description] ||= "#{attribute.to_s.titleize} field on #{self.name.titleize}"

          if !options.include?(:values) && !options.include?(:type)
            if defined_enums.include?(attribute.to_s)
              options[:values] = defined_enums[attribute.to_s].keys.map { |ev| [options[:upcase] ? ev.upcase : ev, ev.titleize] }.to_h
            else
              fail ArgumentError.new("Could not auto-detect the values for enum #{attribute} on #{self.name}")
            end
          end

          enum_type = graphql_enum_types[attribute]
          unless enum_type
            enum_type = options[:type] || GraphQL::EnumType.define do
              name options[:name]
              description options[:description]

              options[:values].each do |value_name, desc|
                value(value_name, desc)
              end
            end

            graphql_enum_types[attribute] = enum_type
          end

          graphql_resolve(attribute) { send(attribute).try(:upcase) } if options[:upcase]
          enum_type
        end

        def graphql_resolvers
          @_graphql_resolvers ||= {}.with_indifferent_access
        end

        # Defines a custom method that is used to resolve this attribute's value when it is included
        # on a GraphQL type.
        def graphql_resolve(attribute, &block)
          fail ArgumentError.new("#{__method__} requires a block") unless block_given?
          graphql_resolvers[attribute] = block
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, GraphQL::Models::ActiveRecordExtension)
