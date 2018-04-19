# frozen_string_literal: true

module GraphQL::Models
  class MutationFieldMap
    attr_accessor :model_type, :find_by, :null_behavior, :fields, :nested_maps, :legacy_nulls

    # These are used when this is a proxy_to or a nested field map
    attr_accessor :name, :association, :has_many, :required, :path

    def initialize(model_type, find_by:, null_behavior:, legacy_nulls:)
      raise ArgumentError, "model_type must be a model" if model_type && !(model_type <= ActiveRecord::Base)
      raise ArgumentError, "null_behavior must be :set_null or :leave_unchanged" unless %i[set_null leave_unchanged].include?(null_behavior)

      @fields = []
      @nested_maps = []
      @path = []
      @model_type = model_type
      @find_by = Array.wrap(find_by)
      @null_behavior = null_behavior
      @legacy_nulls = legacy_nulls

      @find_by.each { |f| attr(f) }
    end

    def types
      GraphQL::Define::TypeDefiner.instance
    end

    def attr(attribute, type: nil, name: nil, required: nil)
      attribute = attribute.to_sym if attribute.is_a?(String)

      if type.nil? && !model_type
        raise ArgumentError, "You must specify a type for attribute #{name}, because its model type is not known until runtime."
      end

      if type.nil? && (attribute == :id || foreign_keys.include?(attribute))
        type = types.ID
      end

      if type.nil? && model_type
        type = Reflection.attribute_graphql_type(model_type, attribute).input
      end

      if required.nil?
        required = model_type ? Reflection.is_required(model_type, attribute) : false
      end

      name ||= attribute.to_s.camelize(:lower)
      name = name.to_s

      detect_field_conflict(name)

      # Delete the field, if it's already in the map
      fields.reject! { |fd| fd[:attribute] == attribute }

      fields << {
        name: name,
        attribute: attribute,
        type: type,
        required: required,
      }
    end

    def proxy_to(association, &block)
      association = association.to_sym if association.is_a?(String)

      reflection = model_type&.reflect_on_association(association)

      if reflection
        unless %i[belongs_to has_one].include?(reflection.macro)
          raise ArgumentError, "Cannot proxy to #{reflection.macro} association #{association} from #{model_type.name}"
        end

        klass = reflection.polymorphic? ? nil : reflection.klass
      else
        klass = nil
      end

      proxy = MutationFieldMap.new(klass, find_by: nil, null_behavior: null_behavior, legacy_nulls: legacy_nulls)
      proxy.association = association
      proxy.instance_exec(&block)

      proxy.fields.each { |f| detect_field_conflict(f[:name]) }
      proxy.nested_maps.each { |m| detect_field_conflict(m.name) }

      proxy.fields.each do |field|
        fields.push({
          name: field[:name],
          attribute: field[:attribute],
          type: field[:type],
          required: field[:required],
          path: [association] + Array.wrap(field[:path]),
        })
      end

      proxy.nested_maps.each do |m|
        m.path.unshift(association)
        nested_maps.push(m)
      end
    end

    def nested(association, find_by: nil, null_behavior:, name: nil, &block)
      unless model_type
        raise ArgumentError, "Cannot use `nested` unless the model type is known at build time."
      end

      association = association.to_sym if association.is_a?(String)
      reflection = model_type.reflect_on_association(association)

      unless reflection
        raise ArgumentError, "Could not find association #{association} on #{model_type.name}"
      end

      if reflection.polymorphic?
        raise ArgumentError, "Cannot used `nested` with polymorphic association #{association} on #{model_type.name}"
      end

      has_many = reflection.macro == :has_many
      required = Reflection.is_required(model_type, association)

      map = MutationFieldMap.new(reflection.klass, find_by: find_by, null_behavior: null_behavior, legacy_nulls: legacy_nulls)
      map.name = name || association.to_s.camelize(:lower)
      map.association = association.to_s
      map.has_many = has_many
      map.required = required

      detect_field_conflict(map.name)

      map.instance_exec(&block)

      nested_maps.push(map)
    end

    def leave_null_unchanged?
      null_behavior == :leave_unchanged
    end

    private

    def detect_field_conflict(name)
      if fields.any? { |f| f[name] == name } || nested_maps.any? { |n| n.name == name }
        raise ArgumentError, "The field #{name} is defined more than once."
      end
    end

    def foreign_keys
      @foreign_keys ||= model_type.reflections.values
        .select { |r| r.macro == :belongs_to }
        .map(&:foreign_key)
        .map(&:to_sym)
    end
  end
end
