module GraphQL
  module Models
    module Identification
      VALID_IDENTIFIER = "[a-zA-Z][a-zA-Z0-9_]+"
      VALID_IDENTIFIER_EXP = /\A#{VALID_IDENTIFIER}\z/

      # For a virtual type, the "type_name" part of the ID will look like this:
      # attachment(OfferLetter, signed_document)
      ATTRIBUTE_TYPE_EXP = %r{
        \A
        (?<name>#{VALID_IDENTIFIER}) # match the name of the virtual type
        \(( # parameters, wrapped with parentheses
          (?<modelType>#{VALID_IDENTIFIER}) # type of model that the field was used on
          (?<parameters>(,#{VALID_IDENTIFIER})*) # additional parameters
        )\)
        \z
      }x

      ATTRIBUTE_TYPES = {}.with_indifferent_access

      def self.is_attribute_type(type_name)
        ATTRIBUTE_TYPE_EXP === type_name
      end

      def self.resolve_attribute_type(type_name, model_id, context)
        match = ATTRIBUTE_TYPE_EXP.match(type_name)
        return nil unless REGISTERED_TYPES.include?(match['name']) && Models.is_model_type(match['modelType'])

        attribute_type = REGISTERED_TYPES[match['name']]
        return nil unless attribute_type.validate(type_name, model_id, context)

        model = Models.resolve_model_type(match['modelType'], model_id, context)
        return nil unless model

        parameters = match['parameters'].split(',')
        attribute_type.resolve(model, *parameters)
      end
    end
  end
end
