module GraphQL::Models
  class MutationFieldMap
    attr_accessor :model_type, :find_by, :null_behavior, :fields, :nested_maps

    # These are used when this is a proxy_to or a nested field map
    attr_accessor :name, :association, :has_many, :required, :path

    def initialize(model_type, find_by:, null_behavior:)
      fail ArgumentError.new("model_type must be a model") if model_type && !(model_type <= ActiveRecord::Base)
      fail ArgumentError.new("null_behavior must be :set_null or :leave_unchanged") unless [:set_null, :leave_unchanged].include?(null_behavior)

      @fields = []
      @nested_maps = []
      @path = []
      @model_type = model_type
      @find_by = Array.wrap(find_by)
      @null_behavior = null_behavior

      @find_by.each { |f| attr(f) }
    end

    def types
      GraphQL::Define::TypeDefiner.instance
    end

    def attr(attribute, type: nil, name: nil, required: false)
      attribute = attribute.to_sym if attribute.is_a?(String)

      if type.nil? && !model_type
        fail ArgumentError.new("You must specify a type for attribute #{name}, because its model type is not known until runtime.")
      end

      if model_type
        column = DefinitionHelpers.get_column(model_type, attribute)

        if column.nil? && type.nil?
          fail ArgumentError.new("You must specify a type for attribute #{name}, because it's not a column on #{model_type}.")
        end

        if column
          type ||= begin
            if attribute == :id || foreign_keys.include?(attribute)
              type = types.ID
            else
              type = column.graphql_type
            end
          end

          required = DefinitionHelpers.detect_is_required(model_type, attribute)
        end
      end

      name ||= attribute.to_s.camelize(:lower)
      name = name.to_s

      detect_field_conflict(name)

      fields.push({
        name: name,
        attribute: attribute,
        type: type,
        required: required
      })
    end

    def proxy_to(association, &block)
      association = association.to_sym if association.is_a?(String)

      reflection = model_type&.reflect_on_association(association)

      if reflection
        unless [:belongs_to, :has_one].include?(reflection.macro)
          fail ArgumentError.new("Cannot proxy to #{reflection.macro} association #{association} from #{model_type.name}")
        end

        klass = reflection.polymorphic? ? nil : reflection.klass
      else
        klass = nil
      end

      proxy = MutationFieldMap.new(klass, find_by: nil, null_behavior: null_behavior)
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
          path: [association] + Array.wrap(field[:path])
        })
      end

      proxy.nested_maps.each do |m|
        m.path.unshift(association)
        nested_maps.push(m)
      end
    end

    def nested(association, find_by: nil, null_behavior:, name: nil, has_many: false, &block)
      unless model_type
        fail ArgumentError.new("Cannot use `nested` unless the model type is known at build time.")
      end

      association = association.to_sym if association.is_a?(String)
      reflection = model_type.reflect_on_association(association)

      unless reflection
        fail ArgumentError.new("Could not find association #{association} on #{model_type.name}")
      end

      if reflection.polymorphic?
        fail ArgumentError.new("Cannot used `nested` with polymorphic association #{association} on #{model_type.name}")
      end

      has_many = reflection.macro == :has_many
      required = DefinitionHelpers.detect_is_required(model_type, association)

      map = MutationFieldMap.new(reflection.klass, find_by: find_by, null_behavior: null_behavior)
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
        fail ArgumentError.new("The field #{name} is defined more than once.")
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
