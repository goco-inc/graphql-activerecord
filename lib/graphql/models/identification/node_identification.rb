module GraphQL
  module Models
    NodeIdentification = GraphQL::Relay::GlobalNodeIdentification.define do
      object_from_id -> (gid, context) do
        return Identification::VIEWER_OBJECT if gid == Identification::VIEWER_ID

        type_name, id = GraphQL::Models::NodeIdentification.from_global_id(gid)

        return Identification.resolve_model_type(type_name, id, context) if Identification.is_model_type(type_name)
        return Identification.resolve_attribute_type(type_name, id, context) if Identification.is_attribute_type(type_name)

        return nil
      end

      type_from_object -> (obj) do
        return Identification::VIEWER_ID if obj == Identification::VIEWER_OBJECT
        return "#{obj.class.name}Graph".safe_constantize if obj.is_a?(ActiveRecord::Base)

        Identification::ATTRIBUTE_TYPES.each do |name, attribute_type|
          return attribute_type.graph_type if attribute_type.detect(obj)
        end

        return nil
      end
    end
  end
end
