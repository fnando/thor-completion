# frozen_string_literal: true

class Thor
  module Completion
    class Powershell
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
        generate_completion_function

        output.join("\n")
      end

      private def generate_completion_function
        output << "using namespace System.Management.Automation"
        output << "using namespace System.Management.Automation.Language"
        output << ""
        output << "Register-ArgumentCompleter -Native -CommandName #{name} -ScriptBlock {"
        output << "    param($wordToComplete, $commandAst, $cursorPosition)"
        output << ""
        output << "    $commandElements = $commandAst.CommandElements"
        output << "    $command = @("
        output << "        '#{name}'"
        output << "        for ($i = 1; $i -lt $commandElements.Count; $i++) {"
        output << "            $element = $commandElements[$i]"
        output << "            if ($element -isnot [StringConstantExpressionAst] -or"
        output << "                $element.StringConstantType -ne [StringConstantType]::BareWord -or"
        output << "                $element.Value.StartsWith('-') -or"
        output << "                $element.Value -eq $wordToComplete) {"
        output << "                break"
        output << "            }"
        output << "            $element.Value"
        output << "        }"
        output << "    ) -join ';'"
        output << ""
        output << "    $completions = @(switch ($command) {"

        generate_command_completions("", commands, [name])

        output << "    })"
        output << ""
        output << "    $completions.Where{ $_.CompletionText -like \"$wordToComplete*\" } |"
        output << "        Sort-Object -Property ListItemText"
        output << "}"
      end

      private def generate_command_completions(prefix, cmds, path)
        path_str = path.join(";")

        # Generate completions for this level
        output << "        #{quote_ps(path_str)} {"

        # Add commands/subcommands
        cmds.reject {|c| c[:hidden] }.each do |cmd|
          cmd_name = cmd[:name]
          cmd_desc = escape_ps(cmd[:description] || "")

          output << "            [CompletionResult]::new(#{quote_ps(cmd_name)}, #{quote_ps(cmd_name)}, [CompletionResultType]::ParameterValue, #{quote_ps(cmd_desc)})"
        end

        # Add global options if at root level
        if path.length == 1
          global_options.reject {|opt| opt[:hidden] }.each do |opt|
            generate_option_completions(opt)
          end
        end

        output << "            break"
        output << "        }"

        # Recursively generate completions for subcommands
        cmds.each do |cmd|
          next if cmd[:hidden]

          cmd_name = cmd[:name]
          new_path = path + [cmd_name]

          # Generate completions for this command's options and arguments
          if cmd[:options]&.any? || cmd[:arguments]&.any?
            cmd_path_str = new_path.join(";")
            output << "        #{quote_ps(cmd_path_str)} {"

            # Add options
            if cmd[:options]&.any?
              cmd[:options].reject {|opt| opt[:hidden] }.each do |opt|
                generate_option_completions(opt)
              end
            end

            # Add arguments completion (file completion as default)
            if cmd[:arguments]&.any?
              arg = cmd[:arguments].first
              if arg[:completion]
                case arg[:completion][:type]
                when "file"
                  output << "            # File completion"
                  output << "            Get-ChildItem -Path . -File | ForEach-Object {"
                  output << "                [CompletionResult]::new($_.Name, $_.Name, [CompletionResultType]::ParameterValue, $_.Name)"
                  output << "            }"
                when "directory"
                  output << "            # Directory completion"
                  output << "            Get-ChildItem -Path . -Directory | ForEach-Object {"
                  output << "                [CompletionResult]::new($_.Name, $_.Name, [CompletionResultType]::ParameterValue, $_.Name)"
                  output << "            }"
                end
              end
            end

            output << "            break"
            output << "        }"
          end

          # Recurse for subcommands
          generate_command_completions("#{prefix}#{cmd_name};", cmd[:subcommands], new_path) if cmd[:subcommands]&.any?
        end
      end

      private def generate_option_completions(opt)
        opt_desc = escape_ps(opt[:description] || "")

        # Add short option if available
        if opt[:short]
          Array(opt[:short]).each do |short|
            short_flag = "-#{short}"
            output << "            [CompletionResult]::new(#{quote_ps(short_flag)}, #{quote_ps(short_flag)}, [CompletionResultType]::ParameterName, #{quote_ps(opt_desc)})"
          end
        end

        # Add long option
        return unless opt[:name]

        long_flag = "--#{opt[:name]}"
        output << "            [CompletionResult]::new(#{quote_ps(long_flag)}, #{quote_ps(long_flag)}, [CompletionResultType]::ParameterName, #{quote_ps(opt_desc)})"

        # For options with enum values, we could add value completions
        # but that would require tracking the previous word, which is complex in PowerShell
      end

      private def quote_ps(str)
        "'#{str.to_s.gsub("'", "''")}'"
      end

      private def escape_ps(str)
        str.to_s.gsub("'", "''")
      end

      private def sanitize_name(name)
        name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
