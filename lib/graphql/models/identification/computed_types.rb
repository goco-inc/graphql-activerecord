module GraphQL
  module Models
    module Identification
      VALID_IDENTIFIER = "[a-zA-Z][a-zA-Z0-9_]+"
      VALID_IDENTIFIER_EXP = /\A#{VALID_IDENTIFIER}\z/

      # For a virtual type, the "type_name" part of the ID will look like this:
      # attachment(OfferLetter, signed_document)
      COMPUTED_TYPE_EXP = %r{
        \A
        (?<name>#{VALID_IDENTIFIER}) # match the name of the virtual type
        \(( # parameters, wrapped with parentheses
          (?<modelType>#{VALID_IDENTIFIER}) # type of model that the field was used on
          (?<fieldArgs>(,#{VALID_IDENTIFIER})+) # name of the field
        )\)
        \z
      }x

      COMPUTED_TYPES = {}.with_indifferent_access

      def self.is_computed_type(type_name)
        COMPUTED_TYPE_EXP === type_name
      end

      def self.resolve_computed_type(type_name, model_id, context)
        match = COMPUTED_TYPE_EXP.match(type_name)
        return nil unless REGISTERED_TYPES.include?(match['name']) && Models.is_model_type(match['modelType'])

        computed_type = REGISTERED_TYPES[match['name']]
        return nil unless computed_type.validate(type_name, model_id, context)

        model = Models.resolve_model_type(match['modelType'], model_id, context)
        return nil unless model

        field_args = match['fieldArgs'].split(',')[1..-1] # strip off empty element from leading comma
        return nil unless field_args.length == computed_type.arity

        computed_type.resolve(model, *field_args)
      end
    end
  end
end
