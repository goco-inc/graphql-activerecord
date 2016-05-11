module GraphQL::Models
  module MutationHelpers
    def self.print_input_fields(field_map, definer, map_name_prefix)
      definer.instance_exec do
        field_map.fields.each do |f|
          field_type = f[:type]

          if f[:required] && !field_map.leave_null_unchanged?
            field_type = field_type.to_non_null_type
          end

          input_field(f[:name], field_type)
        end

        if field_map.leave_null_unchanged?
          input_field('unsetFields', types[!types.String])
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
