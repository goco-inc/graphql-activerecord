# frozen_string_literal: true

module GraphQL::Models
  module MutationHelpers
    def self.apply_changes(field_map, model, inputs, context)
      # This will hold a flattened list of attributes/models that we actually changed
      changes = []

      # Values will now contain the list of inputs that we should actually act on. Any null values should actually
      # be set to null, and missing fields should be skipped.
      values = if field_map.leave_null_unchanged? && field_map.legacy_nulls
        prep_legacy_leave_unchanged(inputs)
      elsif field_map.leave_null_unchanged?
        prep_leave_unchanged(inputs)
      else
        prep_set_null(field_map, inputs)
      end

      values.each do |name, value|
        field_def = field_map.fields.detect { |f| f[:name] == name }

        # Skip this value unless it's a field on the model. Nested fields are handled later.
        next unless field_def

        # Advance to the model that we actually need to change
        change_model = model_to_change(model, field_def[:path], changes, create_if_missing: !value.nil?)
        next if change_model.nil?

        # Apply the change to this model
        apply_field_value(change_model, field_def, value, context, changes)
      end

      # Handle the value nested fields now.
      field_map.nested_maps.each do |child_map|
        next if inputs[child_map.name].nil? && field_map.leave_null_unchanged?

        # Advance to the model that contains the nested fields
        change_model = model_to_change(model, child_map.path, changes, create_if_missing: !inputs[child_map.name].nil?)
        next if change_model.nil?

        # Apply the changes to the nested models
        child_changes = handle_nested_map(field_map, change_model, inputs, context, child_map)

        # Merge the changes with the parent, but prepend the input field path
        child_changes.each do |cc|
          cc[:input_path] = [child_map.name] + Array.wrap(cc[:input_path]) if cc[:input_path]
          changes.push(cc)
        end
      end

      changes
    end

    def self.handle_nested_map(parent_map, parent_model, inputs, context, child_map)
      next_inputs = inputs[child_map.name]

      # Don't do anything if the value is null, and we leave null fields unchanged
      return [] if next_inputs.nil? && parent_map.leave_null_unchanged?

      changes = []
      matches = match_inputs_to_models(parent_model, child_map, next_inputs, changes, context)

      matches.each do |match|
        next if match[:child_model].nil? && match[:child_inputs].nil?

        child_changes = apply_changes(child_map, match[:child_model], match[:child_inputs], context)

        if match[:input_path]
          child_changes.select { |cc| cc[:input_path] }.each do |cc|
            cc[:input_path] = [match[:input_path]] + Array.wrap(cc[:input_path])
          end
        end

        changes.concat(child_changes)
      end

      changes
    end

    def self.match_inputs_to_models(model, child_map, next_inputs, changes, context)
      if !child_map.has_many
        child_model = model.public_send(child_map.association)

        if next_inputs.nil? && !child_model.nil?
          child_model.mark_for_destruction
          changes.push({ model_instance: child_model, action: :destroy })
        elsif child_model.nil? && !next_inputs.nil?
          child_model = model.public_send("build_#{child_map.association}")

          assoc = model.association(child_map.association)
          refl = assoc.reflection

          if refl.options.include?(:as)
            inverse_name = refl.options[:as]
            inverse_assoc = child_model.association(inverse_name)
            inverse_assoc.target = model
            inverse_assoc.inversed = true
          end

          changes.push({ model_instance: child_model, action: :create })
        end

        [{ child_model: child_model, child_inputs: next_inputs }]
      else
        next_inputs = [] if next_inputs.nil?

        # Match up each of the elements in next_inputs with one of the models, based on the `find_by` value.
        associated_models = model.public_send(child_map.association)
        find_by = Array.wrap(child_map.find_by).map(&:to_s)

        if find_by.empty?
          return match_inputs_by_position(model, child_map, next_inputs, changes, associated_models)
        else
          return match_inputs_by_fields(model, child_map, next_inputs, changes, associated_models, find_by, context)
        end
      end
    end

    def self.match_inputs_by_position(_model, _child_map, next_inputs, changes, associated_models)
      count = [associated_models.length, next_inputs.length].max

      matches = []

      # This will give us an array of [number, model, inputs].
      # Either the model or the inputs could be nil, but not both.
      count.times.zip(associated_models.to_a, next_inputs) do |(idx, child_model, inputs)|
        if child_model.nil?
          child_model = associated_models.build
          changes.push({ model_instance: child_model, action: :create })
        end

        if inputs.nil?
          child_model.mark_for_destruction
          changes.push({ model_instance: child_model, action: :destroy })
          next
        end

        matches.push({ child_model: child_model, child_inputs: inputs, input_path: idx })
      end

      matches
    end

    def self.match_inputs_by_fields(_model, child_map, next_inputs, changes, associated_models, find_by, context)
      # Convert the find_by into the field definitions, so that we properly unmap aliased fields
      find_by_defs = find_by.map { |name| child_map.fields.detect { |f| f[:attribute].to_s == name.to_s } }
      name_to_attr = find_by_defs.map { |f| [f[:name], f[:attribute].to_s] }.to_h

      indexed_models = associated_models.index_by { |m| m.attributes.slice(*find_by) }

      # Inputs are a little nasty, the keys have to be converted from camelCase back to snake_case
      indexed_inputs = next_inputs.index_by { |ni| ni.to_h.slice(*name_to_attr.keys) }

      indexed_inputs = indexed_inputs.map do |key, inputs|
        attr_key = {}
        key.each do |name, val|
          # If the input is a Relay ID, convert it to the model's ordinary ID first. Note, this is
          # less than optimal, because it has to fetch the model and then just get its id :(
          field_def = find_by_defs.detect { |d| d[:name] == name }
          if val && field_def[:type].unwrap == GraphQL::ID_TYPE
            val = relay_id_to_model_id(val, context)
            raise GraphQL::ExecutionError, "The value provided for #{field_def[:name]} does not refer to a valid model." unless val
          end

          attr_key[name_to_attr[name]] = val
        end

        [attr_key, inputs]
      end

      indexed_inputs = indexed_inputs.to_h

      # Match each model to its input. If there is no input for it, mark that the model should be destroyed.
      matches = []

      indexed_models.each do |key_attrs, child_model|
        inputs = indexed_inputs[key_attrs]

        if inputs.nil?
          child_model.mark_for_destruction
          changes.push({ model_instance: child_model, action: :destroy })
        else
          matches.push({ child_model: child_model, child_inputs: inputs, input_path: next_inputs.index(inputs) })
        end
      end

      # Build a new model for each input that doesn't have a model
      indexed_inputs.each do |key_attrs, inputs|
        next if indexed_models.include?(key_attrs)

        child_model = associated_models.build
        changes.push({ model_instance: child_model, action: :create })
        matches.push({ child_model: child_model, child_inputs: inputs, input_path: next_inputs.index(inputs) })
      end

      matches
    end

    # Returns the instance of the model that will be changed for this field. If new models are created along the way,
    # they are added to the list of changes.
    def self.model_to_change(starting_model, path, changes, create_if_missing: true)
      model_to_change = starting_model

      Array.wrap(path).each do |ps|
        next_model = model_to_change.public_send(ps)

        return nil if next_model.nil? && !create_if_missing

        unless next_model
          next_model = model_to_change.public_send("build_#{ps}")
          # Even though we may not be changing anything on this model, record it as a change, since it's a new model.
          changes.push({ model_instance: next_model, action: :create })
        end

        model_to_change = next_model
      end

      model_to_change
    end

    def self.apply_field_value(model, field_def, value, context, changes)
      # Special case: If this is an ID field, get the ID from the target model
      if value.present? && field_def[:type].unwrap == GraphQL::ID_TYPE
        value = relay_id_to_model_id(value, context)
        unless value
          raise GraphQL::ExecutionError, "The value provided for #{field_def[:name]} does not refer to a valid model."
        end
      end

      unless model.public_send(field_def[:attribute]) == value
        model.public_send("#{field_def[:attribute]}=", value)

        changes.push({
          model_instance: model,
          input_path: field_def[:name],
          attribute: field_def[:attribute],
          action: model.new_record? ? :create : :update,
        })
      end
    end

    # If the field map has the option leave_null_unchanged, and legacy_nulls is true, then there's an `unsetFields` string
    # array that contains the name of inputs that should be treated as if they are null. We handle that by removing null
    # inputs, and then adding back any unsetFields with null values.
    def self.prep_legacy_leave_unchanged(inputs)
      # String key hash
      values = inputs.to_h.compact

      unset = Array.wrap(values['unsetFields'])
      values.delete('unsetFields')

      unset.each do |name|
        values[name] = nil
      end

      values
    end

    def self.prep_leave_unchanged(inputs)
      inputs.to_h
    end

    # Field map has the option to set_null. Any field that has the value null, or is missing, will be set to null.
    def self.prep_set_null(field_map, inputs)
      values = inputs.to_h.compact

      field_map.fields.reject { |f| values.include?(f[:name]) }.each { |f| values[f[:name]] = nil }
      field_map.nested_maps.reject { |m| values.include?(m.name) }.each { |m| values[m.name] = nil }

      values
    end

    def self.relay_id_to_model_id(relay_id, context)
      target_model = GraphQL::Models.model_from_id.call(relay_id, context)
      target_model&.id
    end
  end
end
