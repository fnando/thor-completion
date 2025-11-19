# frozen_string_literal: true

require "test_helper"

class ZSH < Minitest::Test
  test "converts basic JSON schema to zsh completion" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "help",
          description: "Describe available commands or one specific command"
        },
        {name: "new", description: "Create a new app"}
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "#compdef mycli"
    assert_includes \
      result,
      "'help':'Describe available commands or one specific command'"
    assert_includes result, "'new':'Create a new app'"
    assert_includes result, "_describe 'command' commands"
  end

  test "handles command options" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "new",
          description: "Create a new app",
          options: [
            {
              name: "skip-bundle",
              short: "B",
              description: "Skip bundle install",
              type: "boolean"
            },
            {
              name: "database",
              short: "d",
              description: "Database type",
              type: "string",
              enum: %w[sqlite postgres mysql]
            }
          ]
        }
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "_mycli_new"
    assert_includes result, "skip-bundle"
    assert_includes result, "database"
  end

  test "handles command arguments" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "new",
          description: "Create a new app",
          arguments: [
            {name: "path", description: "Application path", required: true}
          ]
        }
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "_mycli_new"
    assert_includes result, "Application path"
  end

  test "handles global options" do
    schema = {
      name: "mycli",
      globalOptions: [
        {
          name: "verbose", short: "v", description: "Verbose output",
          type: "boolean"
        },
        {name: "config", short: "c", description: "Config file", type: "string"}
      ],
      commands: [
        {name: "help", description: "Show help"}
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "verbose"
    assert_includes result, "config"
  end

  test "handles subcommands" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "db",
          description: "Database commands",
          subcommands: [
            {name: "migrate", description: "Run migrations"},
            {name: "seed", description: "Seed database"}
          ]
        }
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "_mycli_db"
    assert_includes result, "'migrate':'Run migrations'"
    assert_includes result, "'seed':'Seed database'"
  end

  test "handles hidden commands" do
    schema = {
      name: "mycli",
      commands: [
        {name: "public", description: "Public command"},
        {name: "secret", description: "Hidden command", hidden: true}
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "public"
    refute_includes result, "secret"
  end

  test "handles file completion" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "edit",
          description: "Edit file",
          arguments: [
            {
              name: "file",
              description: "File to edit",
              completion: {type: "file", extensions: %w[rb py]}
            }
          ]
        }
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "_files"
  end

  test "handles multiple short options" do
    schema = {
      name: "mycli",
      commands: [
        {
          name: "test",
          description: "Run tests",
          options: [
            {
              name: "quiet",
              short: %w[q s],
              description: "Quiet mode",
              type: "boolean"
            }
          ]
        }
      ]
    }

    converter = Thor::Completion::ZSH.new(schema)
    result = converter.call

    assert_includes result, "quiet"
  end
end
