require 'morpheus/cli/cli_command'

# This is for deleting files and directories!
class Morpheus::Cli::RemoveFileCommand
  include Morpheus::Cli::CliCommand
  set_command_name :rm
  set_command_hidden

  def handle(args)
    print_red_alert "Not yet supported"
    return -1
  end

end
