module GraphQL
  module Models
    module Identification
      class AttributeTypeDefinition
        attr_accessor :name, :graph_type_proc, :identifiers, :detect_proc, :validate_proc, :resolve_proc

        def self.define(&block)
          definer = Definer.new(:name, :graph_type, :identifiers, :detect, :validate, :resolve)
          definer.instance_exec(&block)

          attr_type = AttributeTypeDefinition.new

          attr_type.name = definer.defined_values[:name]
          attr_type.graph_type_proc = definer.defined_values[:graph_type]
          attr_type.identifiers = Array.wrap(definer.defined_values[:identifiers])
          attr_type.detect_proc = definer.defined_values[:detect]
          attr_type.validate_proc = definer.defined_values[:validate]
          attr_type.resolve_proc = definer.defined_values[:resolve]

          attr_type
        end

        def graph_type
          # graph_type_proc could be either a proc that returns a GraphQL type, or the type itself
          graph_type.is_a?(Proc) ? graph_type.call : graph_type
        end

        def detect(object)
          detect_proc.call(object)
        end

        def validate(model_type, *identifiers)
          validate_proc.call(model_type, *identifiers)
        end

        def resolve(model, *identifiers)
          resolve_proc.call(model, *identifiers)
        end
      end
    end
  end
end
