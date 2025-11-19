# frozen_string_literal: true

require "thor"
require "json-schema"

class Thor
  module Completion
    require_relative "completion/version"
    require_relative "completion/schema_validator"
    require_relative "completion/builder"
    require_relative "completion/zsh"
    require_relative "completion/bash"
    require_relative "completion/powershell"
    require_relative "completion/fish"

    def self.generate(shell:, name:, description:, version:, cli:)
      schema = Builder.call(name:, description:, version:, cli:)

      case shell
      when "bash"
        Bash.new(schema).call
      when "zsh"
        ZSH.new(schema).call
      when "powershell"
        Powershell.new(schema).call
      when "fish"
        Fish.new(schema).call
      else
        raise "Unsupported shell: #{shell.inspect}"
      end
    end
  end
end
