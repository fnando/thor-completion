# frozen_string_literal: true

class Thor
  module Completion
    class Bash
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
        generate_main_function
        generate_subcommand_functions

        output << ""
        output << "complete -F _#{name} #{name}"

        output.join("\n")
      end

      private def generate_main_function
        output << "_#{name}() {"
        output << "  local cur prev words cword"
        output << "  if type _init_completion &>/dev/null; then"
        output << "    _init_completion || return"
        output << "  else"
        output << "    # Fallback initialization if bash-completion is not available"
        output << "    COMPREPLY=()"
        output << "    _get_comp_words_by_ref -n : cur prev words cword 2>/dev/null || {"
        output << "      cur=\"${COMP_WORDS[COMP_CWORD]}\""
        output << "      prev=\"${COMP_WORDS[COMP_CWORD-1]}\""
        output << "      words=(\"${COMP_WORDS[@]}\")"
        output << "      cword=$COMP_CWORD"
        output << "    }"
        output << "  fi"
        output << ""
        output << "  local commands=\"#{commands.reject {|c| c[:hidden] }.map {|c| c[:name] }.join(' ')}\""
        output << "  local options=\"#{format_options(global_options)}\""
        output << ""
        output << "  if [[ $cword -eq 1 ]]; then"
        output << "    COMPREPLY=($(compgen -W \"$commands $options\" -- \"$cur\"))"
        output << "    return"
        output << "  fi"
        output << ""
        output << "  local command=\"${words[1]}\""
        output << "  case \"$command\" in"

        commands.each do |cmd|
          next if cmd[:hidden]

          cmd_name = cmd[:name]

          next unless cmd[:subcommands]&.any? || cmd[:options]&.any? || cmd[:arguments]&.any?

          output << "    #{cmd_name})"
          output << "      _#{name}_#{sanitize_name(cmd_name)}"
          output << "      ;;"
        end

        output << "    *)"
        output << "      COMPREPLY=()"
        output << "      ;;"
        output << "  esac"
        output << "}"
        output << ""
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

        if cmd[:subcommands]&.any?
          subcommands = cmd[:subcommands].reject {|c| c[:hidden] }.map {|c| c[:name] }.join(" ")
          output << "  local subcommands=\"#{subcommands}\""
        end

        output << "  local options=\"#{format_options(cmd[:options])}\"" if cmd[:options]&.any?

        # Calculate the position where we are in the command
        depth = parent_names.length + 2 # +2 for program name and command name

        if cmd[:subcommands]&.any?
          output << ""
          output << "  if [[ $cword -eq #{depth} ]]; then"
          output << if cmd[:options]&.any?
                      "    COMPREPLY=($(compgen -W \"$subcommands $options\" -- \"$cur\"))"
                    else
                      "    COMPREPLY=($(compgen -W \"$subcommands\" -- \"$cur\"))"
                    end
          output << "    return"
          output << "  fi"
          output << ""
          output << "  local subcommand=\"${words[#{depth}]}\""
          output << "  case \"$subcommand\" in"

          cmd[:subcommands].each do |subcmd|
            next if subcmd[:hidden]

            subcmd_name = subcmd[:name]

            next unless subcmd[:subcommands]&.any? || subcmd[:options]&.any? || subcmd[:arguments]&.any?

            subcmd_func_name = "_#{name}_#{(parent_names + [sanitize_name(cmd_name), sanitize_name(subcmd_name)]).join('_')}"
            output << "    #{subcmd_name})"
            output << "      #{subcmd_func_name}"
            output << "      ;;"
          end

          output << "    *)"
          output << if cmd[:options]&.any?
                      "      COMPREPLY=($(compgen -W \"$options\" -- \"$cur\"))"
                    else
                      "      COMPREPLY=()"
                    end
          output << "      ;;"
          output << "  esac"
        elsif cmd[:arguments]&.any?
          # Handle positional arguments
          arg = cmd[:arguments].first
          output << ""
          output << "  case \"$prev\" in"

          # Handle options that take values
          if cmd[:options]&.any?
            cmd[:options].reject {|opt| opt[:type] == "boolean" }.each do |opt|
              opt_names = ["--#{opt[:name]}"]
              opt_names << "-#{opt[:short]}" if opt[:short]

              output << "    #{opt_names.join('|')})"
              output << if opt[:enum]&.any?
                          "      COMPREPLY=($(compgen -W \"#{opt[:enum].join(' ')}\" -- \"$cur\"))"
                        elsif opt[:completion]
                          "      #{format_completion_bash(opt[:completion])}"
                        else
                          "      COMPREPLY=($(compgen -f -- \"$cur\"))"
                        end
              output << "      return"
              output << "      ;;"
            end
          end

          output << "  esac"
          output << ""

          if cmd[:options]&.any?
            output << "  if [[ $cur == -* ]]; then"
            output << "    COMPREPLY=($(compgen -W \"$options\" -- \"$cur\"))"
            output << "    return"
            output << "  fi"
            output << ""
          end

          # Default to file completion for arguments
          output << if arg[:completion]
                      "  #{format_completion_bash(arg[:completion])}"
                    else
                      "  COMPREPLY=($(compgen -f -- \"$cur\"))"
                    end
        elsif cmd[:options]&.any?
          # Only options, no arguments or subcommands
          output << ""
          output << "  case \"$prev\" in"

          cmd[:options].reject {|opt| opt[:type] == "boolean" }.each do |opt|
            opt_names = ["--#{opt[:name]}"]
            opt_names << "-#{opt[:short]}" if opt[:short]

            output << "    #{opt_names.join('|')})"
            output << if opt[:enum]&.any?
                        "      COMPREPLY=($(compgen -W \"#{opt[:enum].join(' ')}\" -- \"$cur\"))"
                      elsif opt[:completion]
                        "      #{format_completion_bash(opt[:completion])}"
                      else
                        "      COMPREPLY=($(compgen -f -- \"$cur\"))"
                      end
            output << "      return"
            output << "      ;;"
          end

          output << "  esac"
          output << ""
          output << "  COMPREPLY=($(compgen -W \"$options\" -- \"$cur\"))"
        end

        output << "}"
        output << ""

        # Recursively generate functions for subcommands
        return unless cmd[:subcommands]&.any?

        cmd[:subcommands].each do |subcmd|
          next if subcmd[:hidden]
          next unless subcmd[:subcommands]&.any? || subcmd[:options]&.any? || subcmd[:arguments]&.any?

          generate_command_function(subcmd, parent_names + [sanitize_name(cmd_name)])
        end
      end

      private def format_options(options)
        options.reject {|opt| opt[:hidden] }
               .map {|opt| format_option_name(opt) }
               .flatten
               .join(" ")
      end

      private def format_option_name(opt)
        names = []
        Array(opt[:short]).each {|s| names << "-#{s}" } if opt[:short]
        names << "--#{opt[:name]}" if opt[:name]
        names
      end

      private def format_completion_bash(completion)
        case completion[:type]
        when "directory"
          "COMPREPLY=($(compgen -d -- \"$cur\"))"
        when "static"
          values = completion[:values].join(" ")
          "COMPREPLY=($(compgen -W \"#{values}\" -- \"$cur\"))"
        when "command", "dynamic"
          cmd = completion[:command]
          "COMPREPLY=($(compgen -W \"$(#{cmd})\" -- \"$cur\"))"
        else
          # Default to file completion for "file" type and unknown types
          "COMPREPLY=($(compgen -f -- \"$cur\"))"
        end
      end

      private def sanitize_name(name)
        name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
