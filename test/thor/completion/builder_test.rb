# frozen_string_literal: true

require "test_helper"

class BuilderTest < Minitest::Test
  include Thor::Completion::SchemaValidator

  let(:cli) { Sample::CLI }

  test "converts cli to valid schema" do
    schema = Thor::Completion::Builder.call(
      name: "mycli",
      description: "This is mycli",
      version: "1.2.3",
      cli:
    )
    validate_schema!(schema)
  end
end
