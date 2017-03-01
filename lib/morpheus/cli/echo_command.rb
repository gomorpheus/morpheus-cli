require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

# This is for use in dotfile scripts
class Morpheus::Cli::EchoCommand
  include Morpheus::Cli::CliCommand
  set_command_name :echo
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [<message>]"
      opts.on( '-n', '--nonewline', "do not append a newline to your words" ) do
        append_newline = false
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    out = ""
    out << args.join(' ')
    if append_newline
      out << "\n"
    end
    # print out 
    print cyan + out + reset
    return true
  end

end
