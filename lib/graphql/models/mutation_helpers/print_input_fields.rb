# frozen_string_literal: true

module GraphQL::Models
  module MutationHelpers
    def self.print_input_fields(field_map, definer, map_name_prefix)
      definer.instance_exec do
        field_map.fields.each do |f|
          field_type = f[:type]

          if f[:required] && !field_map.leave_null_unchanged?
            field_type = field_type.to_non_null_type unless field_type.non_null?
          end

          input_field(f[:name], field_type)
        end

        if field_map.leave_null_unchanged? && field_map.legacy_nulls
          field_names = field_map.fields.reject { |f| f[:required] }.map { |f| f[:name].to_s }
          field_names += field_map.nested_maps.reject(&:required).map { |fld| fld.name.to_s }
          field_names = field_names.sort

          unless field_names.empty?
            enum = GraphQL::EnumType.define do
              name "#{map_name_prefix}UnsettableFields"
              field_names.each { |n| value(n, n.to_s.titleize, value: n) }
            end

            input_field('unsetFields', types[!enum])
          end
        end
      end

      # Build the input types for the nested input maps
      field_map.nested_maps.each do |child_map|
        type = build_input_type(child_map, "#{map_name_prefix}#{child_map.name.to_s.classify}")

        if child_map.has_many
          type = type.to_non_null_type.to_list_type
        end

        if child_map.required && !field_map.leave_null_unchanged?
          type = type.to_non_null_type
        end

        definer.instance_exec do
          input_field(child_map.name, type)
        end
      end
    end

    def self.build_input_type(field_map, name)
      type = GraphQL::InputObjectType.define do
        name(name)
        GraphQL::Models::MutationHelpers.print_input_fields(field_map, self, name)
      end
    end
  end
end
