require 'morpheus/cli/cli_command'

# This is for writing STDIN to files(s)
class Morpheus::Cli::TeeCommand
  include Morpheus::Cli::CliCommand
  set_command_name :tee
  set_command_hidden

  def handle(args)
    print_red_alert "Not yet supported"
    return -1
  end

end
