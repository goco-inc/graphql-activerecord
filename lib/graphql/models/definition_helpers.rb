# frozen_string_literal: true

require 'ostruct'

module GraphQL
  module Models
    module DefinitionHelpers
      def self.types
        GraphQL::Define::TypeDefiner.instance
      end

      # Returns a promise that will eventually resolve to the model that is at the end of the path
      def self.load_and_traverse(current_model, path, context)
        cache_model(context, current_model)
        return Promise.resolve(current_model) if path.empty? || current_model.nil?

        association = current_model.association(path[0])

        while !path.empty? && (association.loaded? || attempt_cache_load(current_model, association, context))
          current_model = association.target
          path = path[1..-1]
          cache_model(context, current_model)

          return Promise.resolve(current_model) if path.empty? || current_model.nil?

          association = current_model.association(path[0])
        end

        # If this is a has_many :through, then we need to load the two associations in sequence
        # (eg: Company has_many :health_lines, through: :open_enrollments => load open enrollments, then health lines)

        promise = if association.reflection.options[:through]
          # First step, load the :through association (ie, the :open_enrollments)
          through = association.reflection.options[:through]
          load_and_traverse(current_model, [through], context).then do |intermediate_models|
            # Now, for each of the intermediate models (OpenEnrollment), load the source association (:health_line)
            sources = intermediate_models.map do |im|
              load_and_traverse(im, [association.reflection.source_reflection_name], context)
            end

            # Once all of the eventual models are loaded, flatten the results
            Promise.all(sources).then do |result|
              result = result.flatten
              Helpers.load_association_with(association, result)
            end
          end
        else
          AssociationLoadRequest.new(current_model, path[0], context).load
        end

        promise.then do |next_model|
          next next_model if next_model.blank?
          cache_model(context, next_model)

          if path.length == 1
            sanity = next_model.is_a?(Array) ? next_model[0] : next_model
            next next_model
          else
            DefinitionHelpers.load_and_traverse(next_model, path[1..-1], context)
          end
        end
      end

      # Attempts to retrieve the model from the query's cache. If it's found, the association is marked as
      # loaded and the model is added. This only works for belongs_to and has_one associations.
      def self.attempt_cache_load(model, association, context)
        return false unless context

        reflection = association.reflection
        return false unless %i[has_one belongs_to].include?(reflection.macro)

        if reflection.macro == :belongs_to
          target_id = model.send(reflection.foreign_key)

          # If there isn't an associated model, mark the association loaded and return
          if target_id.nil?
            mark_association_loaded(association, nil)
            return true
          end

          # If the associated model isn't cached, return false
          target = context.cached_models.detect { |m| m.is_a?(association.klass) && m.id == target_id }
          return false unless target

          # Found it!
          mark_association_loaded(association, target)
          return true
        else
          target = context.cached_models.detect do |m|
            m.is_a?(association.klass) && m.send(reflection.foreign_key) == model.id && (!reflection.options.include?(:as) || m.send(reflection.type) == model.class.name)
          end

          return false unless target

          mark_association_loaded(association, target)
          return true
        end
      end

      def self.cache_model(context, model)
        return unless context
        context.cached_models.merge(Array.wrap(model))
      end

      def self.mark_association_loaded(association, target)
        association.loaded!
        association.target = target
        association.set_inverse_instance(target) unless target.nil?
      end

      def self.traverse_path(base_model, path, _context)
        model = base_model
        path.each do |segment|
          return nil unless model
          model = model.public_send(segment)
        end

        model
      end

      # Stores metadata about GraphQL fields that are available on this model's GraphQL type.
      # @param metadata Should be a hash that contains information about the field's definition, including :macro and :type
      def self.register_field_metadata(graph_type, field_name, metadata)
        field_name = field_name.to_s

        field_meta = graph_type.instance_variable_get(:@field_metadata)
        field_meta ||= graph_type.instance_variable_set(:@field_metadata, {})
        field_meta[field_name] = OpenStruct.new(metadata).freeze
      end
    end
  end
end
