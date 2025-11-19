# frozen_string_literal: true

require "thor"
require_relative "../../lib/thor-completion"

module Sample
  class NestedCommand < Thor
    desc "info", "Show nested info"
    option :detailed,
           type: :boolean,
           default: false,
           desc: "Show detailed information"
    option :output_path,
           type: :string,
           desc: "Path to save the output"
    def info
      puts "running utils:nested:info"
    end
  end

  class UtilsCommand < Thor
    desc "nested SUBCOMMAND ...ARGS", "Nested utility commands"
    subcommand "nested", NestedCommand

    desc "cleanup", "Clean up temporary files"
    option :force,
           type: :boolean,
           default: false,
           desc: "Force cleanup without confirmation",
           aliases: "-f"
    def cleanup
      puts "running utils:cleanup"
    end

    desc "status", "Show system status"
    def status
      puts "running utils:status"
    end

    desc "hidden_command", "This command is hidden"
    option :secret,
           type: :string,
           desc: "A secret option",
           hide: true
    def hidden_command
      puts "running utils:hidden_command"
    end
  end

  class CLI < Thor
    desc "utils SUBCOMMAND ...ARGS", "Utility commands"
    subcommand "utils", UtilsCommand

    class_option :very_verbose,
                 type: :boolean,
                 default: false,
                 desc: "Enable very verbose output",
                 aliases: "-vv"

    desc "new PATH", "Create a new app"
    option :skip_bundle, type: :boolean,
                         default: false,
                         desc: "Skip bundle install",
                         aliases: "-B"
    def new(path)
      puts "running new with #{path.inspect}"
    end

    desc "completion", "Generate shell completion script"
    option :shell,
           type: :string,
           required: true,
           enum: %w[bash zsh powershell fish]
    def completion
      puts Thor::Completion.generate(
        name: "mycli",
        description: "This is mycli",
        version: "1.2.3",
        cli: self.class,
        shell: options.shell
      )
    end
  end
end
