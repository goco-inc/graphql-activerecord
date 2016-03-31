module GraphQL
  module Models
    def self.build_node_identification
      GraphQL::Relay::GlobalNodeIdentification.define do
        object_from_id -> (gid, context) do
          return Identification::VIEWER_OBJECT if gid == Identification::VIEWER_ID

          type_name, id = GraphQL::Relay::GlobalNodeIdentification.from_global_id(gid)

          return Identification.resolve_model_type(type_name, id, context) if Identification.is_model_type(type_name)
          return Identification.resolve_computed_type(type_name, id, context) if Identification.is_computed_type(type_name)

          # If we have a fallback method for identifying unknown gid's, invoke it
          return GraphQL::Models.object_from_id.call(type_name, id, context) if GraphQL::Models.object_from_id

          return nil
        end

        type_from_object -> (obj) do
          return Identification::VIEWER_ID if obj == Identification::VIEWER_OBJECT
          return "#{obj.class.name}Graph".safe_constantize if obj.is_a?(ActiveRecord::Base)

          Identification::COMPUTED_TYPES.each do |name, computed_type|
            graph_type = computed_type.detect(obj)
            return graph_type if graph_type
          end

          # If we have a fallback method for getting unknown types, invoke it
          return GraphQL::Models.type_from_object.call(obj) if GraphQL::Models.type_from_object
          
          return nil
        end
      end
    end
  end
end
