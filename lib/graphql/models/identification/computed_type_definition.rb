module GraphQL
  module Models
    module Identification
      class ComputedTypeDefinition
        attr_accessor :name, :graph_type_proc, :detect_proc, :validate_proc, :resolve_proc, :arity, :location

        DEFINED_VALUES = [:name, :graph_type, :detect, :validate, :resolve]

        def self.define(&block)
          definer = Definer.new(*DEFINED_VALUES)
          definer.instance_exec(&block)

          missing_values = DEFINED_VALUES - definer.defined_values.keys
          if missing_values.any?
            fail StandardError.new("Computed type is missing values: #{missing_values.join(', ')}; at #{block.source_location.join(':')}")
          end

          computed_type = ComputedTypeDefinition.new

          # Arity describes the number of arguments that the computed type expects when it's being used in a model.
          # If the graph_type proc takes optional arguments, it will be passed additional arguments that provide
          # more context, such as the graph_type, field options, etc.
          arguments = definer.defined_values[:graph_type].parameters
          arity = arguments.select { |arg_def| arg_def[0] == :req }.count

          if arity == 0
            fail StandardError.new("The graph_type procs for computed types must take at least one mandatory arguments. Check the `graph_type` for the computed type #{definer.defined_values[:name]}, at #{block.source_location.join(':')}.")
          end

          computed_type.name = definer.defined_values[:name]
          computed_type.graph_type_proc = definer.defined_values[:graph_type]
          computed_type.arity = arity
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

        def detect(object)
          detect_proc.call(object)
        end

        def validate(model_type, *identifiers)
          validate_proc.call(model_type, *identifiers)
        end

        def resolve(model, *identifiers)
          resolve_proc.call(model, *identifiers)
        end

        def graph_type(model_type, field_args)
          # Look at the parameters that the proc expects. We'll pass in the field args as the mandatory, but if it
          # also takes keyword arguments, we'll pass those in as well.
          available_keywords = { model_type: model_type }

          arguments = graph_type_proc.parameters
          explicit_keys = arguments.select { |arg_def| arg_def[0] == :key || arg_def[0] == :keyreq }.map { |arg_def| arg_def[1] }
          takes_optional_keys = arguments.any? { |arg_def| arg_def[0] == :keyrest || arg_def[0] == :rest }

          if takes_optional_keys
            graph_type_proc.call(*field_args, **available_keywords)
          elsif explicit_keys.any?
            graph_type_proc.call(*field_args, **available_keywords.slice(*explicit_keys))
          else
            graph_type_proc.call(*field_args)
          end
        end
      end
    end
  end
end
