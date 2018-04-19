# frozen_string_literal: true

module GraphQL::Models
  module MutationHelpers
    def self.validate_changes(inputs, field_map, root_model, context, all_changes)
      invalid_fields = {}
      unknown_errors = []

      changed_models = all_changes.group_by { |c| c[:model_instance] }

      changed_models.reject { |m, _v| m.valid? }.each do |model, changes|
        attrs_to_field = changes
          .select { |c| c[:attribute] && c[:input_path] }
          .map { |c| [c[:attribute], c[:input_path]] }
          .to_h

        model.errors.each do |attribute, message|
          attribute = attribute.to_sym if attribute.is_a?(String)

          # Cheap check, see if this is a field that the user provided a value for...
          if attrs_to_field.include?(attribute)
            add_error(attribute, message, attrs_to_field[attribute], invalid_fields)
          else
            # Didn't provide a value, expensive check... trace down the input field
            path = detect_input_path_for_attribute(model, attribute, inputs, field_map, root_model, context)

            if path
              add_error(attribute, message, path, invalid_fields)
            else
              unknown_errors.push({
                modelType: model.class.name,
                modelRid: model.id,
                attribute: attribute,
                message: message,
              })
            end
          end
        end
      end

      unless invalid_fields.empty? && unknown_errors.empty?
        raise ValidationError.new(invalid_fields, unknown_errors)
      end
    end

    def self.add_error(_attribute, message, path, invalid_fields)
      path = Array.wrap(path)

      current = invalid_fields
      path[0..-2].each do |ps|
        current = current[ps] ||= {}
      end

      current[path[-1]] = message
    end

    # Given a model and an attribute, returns the path of the input field that would modify that attribute
    def self.detect_input_path_for_attribute(target_model, attribute, inputs, field_map, starting_model, context)
      # Case 1: The input field is inside of this field map.
      candidate_fields = field_map.fields.select { |f| f[:attribute] == attribute }

      candidate_fields.each do |field|
        # Walk to this field. If the model we get is the same as the target model, we found a match.
        candidate_model = model_to_change(starting_model, field[:path], [], create_if_missing: false)
        return Array.wrap(field[:name]) if candidate_model == target_model
      end

      # Case 2: The input field *is* a nested map
      candidate_maps = field_map.nested_maps.select { |m| m.association == attribute.to_s }

      candidate_maps.each do |map|
        # Walk to this field. If the model we get is the same as the target model, we found a match.
        candidate_model = model_to_change(starting_model, map.path, [], create_if_missing: false)
        return Array.wrap(map.name) if candidate_model == target_model
      end

      # Case 3: The input field is somewhere inside of a nested field map.
      field_map.nested_maps.each do |child_map|
        # If we don't have the values for this map, it can't be the right one.
        next if inputs[child_map.name].blank?

        # Walk to the model that contains the nested field
        candidate_model = model_to_change(starting_model, child_map.path, [], create_if_missing: false)

        # If the model for this map doesn't exist, it can't be the one we need, because the target_model does exist.
        next if candidate_model.nil?

        # Match up the inputs with the models, and then check each of them.
        candidate_matches = match_inputs_to_models(candidate_model, child_map, inputs[child_map.name], [], context)

        candidate_matches.each do |m|
          result = detect_input_path_for_attribute(target_model, attribute, m[:child_inputs], child_map, m[:child_model], context)
          next if result.nil?

          path = Array.wrap(result)
          path.unshift(m[:input_path]) if m[:input_path]
          return path
        end
      end

      nil
    end
  end
end
