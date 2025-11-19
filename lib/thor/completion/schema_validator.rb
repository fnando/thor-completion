# frozen_string_literal: true

class Thor
  module Completion
    module SchemaValidator
      def validate_schema!(schema)
        schema_path = File.join(__dir__, "schema.json")
        errors = JSON::Validator.fully_validate("file://#{schema_path}", schema)

        return if errors.empty?

        raise ArgumentError, "Invalid attributes: #{errors.first}"
      end
    end
  end
end
