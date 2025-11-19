# frozen_string_literal: true

class Thor
  module Completion
    class Fish
      include SchemaValidator

      attr_reader :output, :schema, :name, :commands, :global_options

      def initialize(schema)
        validate_schema!(schema)

        @schema = schema
        @name = schema[:name]
        @commands = schema[:commands] || []
        @global_options = schema[:globalOptions] || []
        @output = []
      end

      def call
        # Add a description comment for the command itself
        output << "# #{name} - #{schema[:description]}" if schema[:description]
        output << ""

        generate_completions

        output.join("\n")
      end

      private def generate_completions
        # Generate completions for main commands
        commands.reject {|c| c[:hidden] }.each do |cmd|
          cmd_name = cmd[:name]
          cmd_desc = escape_fish(cmd[:description] || "")

          output << "complete -c #{name} -n \"__fish_use_subcommand\" -a #{cmd_name} -d #{quote_fish(cmd_desc)}"
        end

        # Generate global options
        global_options.reject {|opt| opt[:hidden] }.each do |opt|
          generate_option_completion(opt, "__fish_use_subcommand")
        end

        # Generate completions for subcommands
        commands.each do |cmd|
          next if cmd[:hidden]

          generate_command_completions(cmd, [cmd[:name]])
        end
      end

      private def generate_command_completions(cmd, path)
        condition = build_condition(path)

        # Generate subcommands
        if cmd[:subcommands]&.any?
          cmd[:subcommands].reject {|c| c[:hidden] }.each do |subcmd|
            subcmd_name = subcmd[:name]
            subcmd_desc = escape_fish(subcmd[:description] || "")

            output << "complete -c #{name} -n #{quote_fish(condition)} -a #{subcmd_name} -d #{quote_fish(subcmd_desc)}"
          end
        end

        # Generate options
        if cmd[:options]&.any?
          cmd[:options].reject {|opt| opt[:hidden] }.each do |opt|
            generate_option_completion(opt, condition)
          end
        end

        # Generate argument completions
        if cmd[:arguments]&.any?
          arg = cmd[:arguments].first
          if arg[:completion]
            case arg[:completion][:type]
            when "directory"
              output << "complete -c #{name} -n #{quote_fish(condition)} -x -a '(__fish_complete_directories)'"
              # For "file" type or others, Fish will provide file completion by default
            end
          end
          # Fish provides file completion by default, so we don't need to add -F
        end

        # Recursively generate completions for subcommands
        return unless cmd[:subcommands]&.any?

        cmd[:subcommands].each do |subcmd|
          next if subcmd[:hidden]

          generate_command_completions(subcmd, path + [subcmd[:name]])
        end
      end

      private def generate_option_completion(opt, condition)
        opt_desc = escape_fish(opt[:description] || "")

        # Build the base completion command
        base_cmd = "complete -c #{name} -n #{quote_fish(condition)}"

        # Add short and long options
        if opt[:short]
          shorts = Array(opt[:short])

          shorts.each do |short|
            parts = [base_cmd, "-s #{short}"]
            parts << "-l #{opt[:name]}" if opt[:name]
            parts << "-d #{quote_fish(opt_desc)}" if opt_desc && !opt_desc.empty?

            # Add value requirements for non-boolean options
            if opt[:type] != "boolean"
              parts << "-r" # require argument

              if opt[:enum]&.any?
                # Add enum values as completions
                values = opt[:enum].map {|v| escape_fish(v) }.join(" ")
                parts << "-a #{quote_fish(values)}"
              end
            end

            output << parts.join(" ")
          end

          # If there's also a long option and multiple shorts, add long-only completion
          if opt[:name] && shorts.any?
            parts = [base_cmd, "-l #{opt[:name]}"]
            parts << "-d #{quote_fish(opt_desc)}" if opt_desc && !opt_desc.empty?

            if opt[:type] != "boolean"
              parts << "-r"
              if opt[:enum]&.any?
                values = opt[:enum].map {|v| escape_fish(v) }.join(" ")
                parts << "-a #{quote_fish(values)}"
              end
            end

            output << parts.join(" ")
          end
        elsif opt[:name]
          # Long option only
          parts = [base_cmd, "-l #{opt[:name]}"]
          parts << "-d #{quote_fish(opt_desc)}" if opt_desc && !opt_desc.empty?

          if opt[:type] != "boolean"
            parts << "-r"
            if opt[:enum]&.any?
              values = opt[:enum].map {|v| escape_fish(v) }.join(" ")
              parts << "-a #{quote_fish(values)}"
            end
          end

          output << parts.join(" ")
        end
      end

      private def build_condition(path)
        # Build a Fish condition that checks if we're in the right subcommand context
        # For example: "__fish_seen_subcommand_from utils; and __fish_seen_subcommand_from nested"
        conditions = path.map do |cmd|
          "__fish_seen_subcommand_from #{cmd}"
        end

        if conditions.length > 1
          # For nested commands, we need to ensure we're in the right context
          conditions.join("; and ")
        else
          conditions.first
        end
      end

      private def quote_fish(str)
        # Fish uses single quotes, escape single quotes by ending the string,
        # adding an escaped quote, and starting a new string
        "'#{str.to_s.gsub("'", "'\\''")}'"
      end

      private def escape_fish(str)
        str.to_s.gsub("'", "\\'")
      end

      private def sanitize_name(name)
        name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
