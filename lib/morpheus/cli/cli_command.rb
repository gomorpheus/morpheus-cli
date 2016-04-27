require 'morpheus/cli/cli_registry'

module Morpheus
  module Cli
    # Module to be included by every CLI command so that commands get registered
    module CliCommand

      def self.included(klass)
        Morpheus::Cli::CliRegistry.add(klass)
        klass.extend ClassMethods
      end

      module ClassMethods
        def cli_command_name(cmd_name)
          Morpheus::Cli::CliRegistry.add(self, cmd_name)
        end
      end
    end
  end
end
