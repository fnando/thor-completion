# frozen_string_literal: true

class Thor
  module Completion
    class ZSH
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
        output << "#compdef #{name}"
        output << ""

        generate_subcommand_functions
        generate_main_function

        output << "compdef _#{name} #{name}"
        output.join("\n")
      end

      private def generate_main_function
        output << "_#{name}() {"
        output << "  local context state line"
        output << "  typeset -A opt_args"
        output << ""

        if commands.any?
          output << "  local -a commands"
          output << "  commands=("
          commands.each do |cmd|
            next if cmd[:hidden]

            cmd_name = cmd[:name]
            cmd_desc = cmd[:description] || ""
            output << "    #{quote(cmd_name)}:#{quote(escape_description(cmd_desc))}"
          end
          output << "  )"
          output << ""
        end

        # Build _arguments call
        args = []

        # Add global options
        global_options.each do |opt|
          result = format_option(opt)
          if result.is_a?(Array)
            args.concat(result)
          elsif result
            args << result
          end
        end

        # Add command selection if we have commands
        if commands.any?
          args << "'1: :->command'"
          args << "'*::arg:->args'"
        end

        if args.any?
          output << "  _arguments -C \\"
          args.each_with_index do |arg, idx|
            line = "    #{arg}"
            line += " \\" unless idx == args.length - 1
            output << line
          end
          output << ""
        end

        if commands.any?
          output << "  case $state in"
          output << "    command)"
          output << "      _describe 'command' commands"
          output << "      ;;"
          output << "    args)"
          output << "      case $words[1] in"

          commands.each do |cmd|
            next if cmd[:hidden]

            cmd_name = cmd[:name]
            output << "        #{cmd_name})"
            output << if cmd[:subcommands]&.any? || cmd[:options]&.any? || cmd[:arguments]&.any?
                        "          _#{name}_#{sanitize_name(cmd_name)}"
                      else
                        "          # No additional completion"
                      end
            output << "          ;;"
          end

          output << "      esac"
          output << "      ;;"
          output << "  esac"
        end

        output << "}"
      end

      private def generate_subcommand_functions
        commands.each do |cmd|
          next if cmd[:hidden]
          next unless cmd[:subcommands]&.any? || cmd[:options]&.any? || cmd[:arguments]&.any?

          generate_command_function(cmd, [])
        end
      end

      private def generate_command_function(cmd, parent_names)
        cmd_name = cmd[:name]
        func_name = "_#{name}_#{(parent_names + [sanitize_name(cmd_name)]).join('_')}"

        output << "#{func_name}() {"

        # Handle subcommands
        if cmd[:subcommands]&.any?
          output << "  local -a subcommands"
          output << "  subcommands=("
          cmd[:subcommands].each do |subcmd|
            next if subcmd[:hidden]

            subcmd_name = subcmd[:name]
            subcmd_desc = subcmd[:description] || ""
            output << "    #{quote(subcmd_name)}:#{quote(escape_description(subcmd_desc))}"
          end
          output << "  )"
          output << ""
        end

        # Build arguments
        args = []

        # Add command-specific options
        if cmd[:options]&.any?
          cmd[:options].each do |opt|
            result = format_option(opt)
            if result.is_a?(Array)
              args.concat(result)
            elsif result
              args << result
            end
          end
        end

        # Add positional arguments
        if cmd[:arguments]&.any? && !cmd[:subcommands]&.any?
          cmd[:arguments].each_with_index do |arg, idx|
            args << format_argument(arg, idx + 1)
          end
        elsif cmd[:subcommands]&.any?
          args << "'1: :->subcommand'"
          args << "'*::arg:->args'"
        end

        if args.any?
          output << "  _arguments \\"
          args.each_with_index do |arg, idx|
            line = "    #{arg}"
            line += " \\" unless idx == args.length - 1
            output << line
          end

          # If we have subcommands, add state handling
          if cmd[:subcommands]&.any?
            output << ""
            output << "  case $state in"
            output << "    subcommand)"
            output << "      _describe 'subcommand' subcommands"
            output << "      ;;"
            output << "    args)"
            output << "      case $words[1] in"
            cmd[:subcommands].each do |subcmd|
              next if subcmd[:hidden]

              subcmd_name = subcmd[:name]
              output << "        #{subcmd_name})"

              # Check if subcommand has options, arguments, or its own subcommands
              if subcmd[:subcommands]&.any? || subcmd[:options]&.any? || subcmd[:arguments]&.any?
                subcmd_func_name = "_#{name}_#{(parent_names + [
                  sanitize_name(cmd_name), sanitize_name(subcmd_name)
                ]).join('_')}"
                output << "          #{subcmd_func_name}"
              else
                output << "          # No additional completion"
              end
              output << "          ;;"
            end
            output << "      esac"
            output << "      ;;"
            output << "  esac"
          end
        elsif cmd[:subcommands]&.any?
          output << "  _describe 'subcommand' subcommands"
        end

        output << "}"
        output << ""

        # Recursively generate functions for subcommands
        return unless cmd[:subcommands]&.any?

        cmd[:subcommands].each do |subcmd|
          next if subcmd[:hidden]
          next unless subcmd[:subcommands]&.any? || subcmd[:options]&.any? || subcmd[:arguments]&.any?

          generate_command_function(subcmd,
                                    parent_names + [sanitize_name(cmd_name)])
        end
      end

      private def format_option(opt)
        return nil if opt[:hidden]

        opt_name = opt[:name]
        opt_short = opt[:short]
        opt_desc = opt[:description] || ""
        opt_type = opt[:type] || "boolean"

        # Build the option spec
        spec_parts = []

        # Handle short and long options
        shorts = Array(opt_short).compact
        if shorts.any? && opt_name
          # Both short and long options - always list separately for compatibility
          exclusion = "(#{shorts.map {|s| "-#{s}" }.join(' ')} --#{opt_name})"
          shorts.each do |s|
            spec_parts << "'#{exclusion}-#{s}[#{escape_description(opt_desc)}]'"
          end
          spec_parts << "'#{exclusion}--#{opt_name}[#{escape_description(opt_desc)}]'"
        elsif shorts.any?
          # Only short options
          if shorts.length > 1
            exclusion = "(#{shorts.map {|s| "-#{s}" }.join(' ')})"
            flags = "{#{shorts.map {|s| "-#{s}" }.join(',')}}"
            spec_parts << "'#{exclusion}#{flags}[#{escape_description(opt_desc)}]'"
          else
            spec_parts << "'-#{shorts.first}[#{escape_description(opt_desc)}]'"
          end
        elsif opt_name
          # Only long option
          spec_parts << "'--#{opt_name}[#{escape_description(opt_desc)}]'"
        else
          return nil
        end

        # Add value completion for non-boolean options
        if opt_type != "boolean"
          spec_parts = spec_parts.map do |spec|
            # Remove the closing bracket and quote
            spec = spec.sub(/\]'$/, "")

            if opt[:enum]&.any?
              # Enum values
              values = opt[:enum].map {|v| escape_value(v) }.join(" ")
              spec + "]:value:(#{values})'"
            elsif opt[:completion]
              add_completion_spec(spec, opt[:completion])
            else
              # Generic value
              spec + "]:#{opt_type}:'"
            end
          end
        end

        spec_parts.length == 1 ? spec_parts[0] : spec_parts
      end

      private def format_argument(arg, position)
        arg_name = arg[:name]
        arg_desc = arg[:description] || arg_name
        variadic = arg[:variadic] ? "*" : ""
        pos = variadic.empty? ? position.to_s : ""

        if arg[:completion]
          completion = format_completion(arg[:completion])
          "'#{variadic}#{pos}:#{arg_desc}:#{completion}'"
        elsif arg[:required] == false
          "'#{variadic}#{pos}::#{arg_desc}:_files'"
        else
          "'#{variadic}#{pos}:#{arg_desc}:_files'"
        end
      end

      private def add_completion_spec(spec, completion)
        comp_spec = format_completion(completion)
        spec + "]:value:#{comp_spec}'"
      end

      private def format_completion(completion)
        case completion[:type]
        when "static"
          values = completion[:values].map {|v| escape_value(v) }.join(" ")
          "(#{values})"
        when "file"
          if completion[:pattern]
            "_files -g #{quote(completion[:pattern])}"
          elsif completion[:extensions]&.any?
            patterns = completion[:extensions].map do |ext|
              "*.#{ext}"
            end.join(" ")
            "_files -g #{quote("{#{patterns}}")}"
          else
            "_files"
          end
        when "directory"
          "_directories"
        when "command"
          "($#{completion[:command]})"
        when "dynamic"
          "($(#{completion[:command]}))"
        else
          "_files"
        end
      end

      private def escape_description(desc)
        desc.to_s.tr("\n", " ").gsub("'", "'\\\\''").gsub(/[\[\]]/, '\\\\\&')
      end

      private def escape_value(value)
        value.to_s.gsub("'", "'\\\\''").gsub(/\s/, '\\\\\&')
      end

      private def quote(str)
        "'#{str}'"
      end

      private def sanitize_name(name)
        name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
