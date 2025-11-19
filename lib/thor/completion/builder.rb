# frozen_string_literal: true

class Thor
  module Completion
    class Builder
      extend SchemaValidator

      def self.call(name:, description:, version:, cli:)
        schema = {
          name:,
          description:,
          version:,
          commands: [],
          subcommands: [],
          globalOptions: []
        }

        build_command(cli, schema)

        cli.class_options.each_value do |option|
          schema[:globalOptions] += build_option(option)
        end

        schema
      end

      def self.build_command(cli, parent)
        cli.options.each_value do |option|
          parent[:options] += build_option(option)
        end

        cli.all_commands.each_value do |command|
          cmd_schema = {
            name: command.name,
            description: command.description || "",
            options: command.options.each_value.flat_map { build_option(it) }
          }

          # Extract positional arguments from method parameters
          if cli.instance_methods(false).include?(command.name.to_sym)
            method = cli.instance_method(command.name.to_sym)
            arguments = extract_arguments(method)
            cmd_schema[:arguments] = arguments if arguments.any?
          end

          # Check if this command has subcommands
          subcommand_class = cli.subcommand_classes[command.name]
          if subcommand_class
            cmd_schema[:subcommands] = []

            # Recursively build subcommands
            build_subcommands(subcommand_class, cmd_schema)
          end

          parent[:commands] << cmd_schema
        end
      end

      def self.resolve_completion(value)
        value = value.to_s

        return "file" if value == "file" || value.end_with?("_file")
        return "directory" if value == "dir" || value.match?(/_dir(ectory)?$/)
        return "directory" if value == "folder" || value.end_with?("_folder")

        nil
      end

      def self.build_subcommands(cli, parent)
        cli.all_commands.each_value do |command|
          subcmd_schema = {
            name: command.name,
            description: command.description || "",
            options: command.options.each_value.flat_map { build_option(it) }
          }

          # Extract positional arguments from method parameters
          if cli.instance_methods(false).include?(command.name.to_sym)
            method = cli.instance_method(command.name.to_sym)
            arguments = extract_arguments(method)
            subcmd_schema[:arguments] = arguments if arguments.any?
          end

          # Check if this subcommand has its own subcommands
          subcommand_class = cli.subcommand_classes[command.name]
          if subcommand_class
            subcmd_schema[:subcommands] = []

            # Recursively build nested subcommands
            build_subcommands(subcommand_class, subcmd_schema)
          end

          parent[:subcommands] << subcmd_schema
        end
      end

      def self.extract_arguments(method)
        values = method
                 .parameters
                 .select {|type, _| %i[req opt rest].include?(type) } # rubocop:disable Style/HashSlice

        values.map do |type, name|
          arg_hash = {
            name: name.to_s,
            description: name.to_s.tr("_", " ").capitalize,
            required: type == :req,
            variadic: type == :rest
          }

          # Add completion hint if available
          completion = resolve_completion(name)
          arg_hash[:completion] = {type: completion} if completion

          arg_hash
        end
      end

      def self.build_option(option)
        dasherize = proc { it.to_s.tr("_", "-") }
        name = dasherize.call(option.name)

        [].tap do |list|
          short_opts = option.aliases.map { dasherize.call(it.gsub(/^-+/, "")) }
          opt_hash = {
            name:,
            type: option.type.to_s,
            description: option.description || "",
            required: option.required,
            repeatable: option.repeatable || false,
            default: option.default,
            enum: Array(option.enum),
            hidden: option.hide || false
          }

          if (completion = resolve_completion(option.name))
            opt_hash[:completion] = completion
          end

          # Only add short if there are aliases
          if short_opts.any?
            opt_hash[:short] =
              short_opts.length == 1 ? short_opts.first : short_opts
          end

          list << opt_hash

          if option.type == :boolean
            list << {
              name: "no-#{name}",
              type: option.type.to_s,
              description: "",
              required: false,
              repeatable: option.repeatable || false,
              hidden: option.hide || false
            }

            list << {
              name: "skip-#{name}",
              type: option.type.to_s,
              description: "",
              required: false,
              repeatable: option.repeatable || false,
              hidden: option.hide || false
            }
          end
        end
      end
    end
  end
end
