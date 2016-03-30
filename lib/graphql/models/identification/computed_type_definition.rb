module GraphQL
  module Models
    module Identification
      class ComputedTypeDefinition
        attr_accessor :name, :graph_type_proc, :identifiers, :detect_proc, :validate_proc, :resolve_proc, :arity, :location

        def self.define(&block)
          definer = Definer.new(:name, :graph_type, :identifiers, :detect, :validate, :resolve)
          definer.instance_exec(&block)

          arity = definer.defined_values[:graph_type].arity

          if arity === 0
            fail StandardError.new("The graph_type procs for computed types must take at least one argument. Check the `graph_type` for the computed type #{definer.defined_values[:name]}, at #{block.source_location.join(':')}.")
          end

          computed_type = ComputedTypeDefinition.new

          computed_type.name = definer.defined_values[:name]
          computed_type.graph_type_proc = definer.defined_values[:graph_type]
          computed_type.arity = arity
          computed_type.identifiers = Array.wrap(definer.defined_values[:identifiers])
          computed_type.detect_proc = definer.defined_values[:detect]
          computed_type.validate_proc = definer.defined_values[:validate]
          computed_type.resolve_proc = definer.defined_values[:resolve]
          computed_type.location = block.source_location.join(':')

          if computed_type.validate_proc.arity != arity + 1
            fail StandardError.new("The validate proc for the computed type #{computed_type.name} should take #{arity + 1} arguments. Check the `validate` for the computed type #{definer.defined_values[:name]}, at #{computed_type.location}.")
          end

          if computed_type.resolve_proc.arity != arity + 1
            fail StandardError.new("The resolve proc for the computed type #{computed_type.name} should take #{arity + 1} arguments. Check the `resolve` for the computed type #{definer.defined_values[:name]}, at #{computed_type.location}.")
          end

          computed_type
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
