require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

# This is for use in dotfile scripts
# It allows you to turn colors on or off globally
class Morpheus::Cli::ColoringCommand
  include Morpheus::Cli::CliCommand
  set_command_name :coloring
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [on|off|on?|off?]"
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
      opts.footer = "Enable [on] or Disable [off] ANSI Colors for all output.\n" + 
                    "Use on? and off? to check the current value."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    exit_code = 0
    subcmd = args[0].to_s.strip
    if subcmd == "on"
      Term::ANSIColor::coloring = true
    elsif subcmd == "off"
      Term::ANSIColor::coloring = false
    elsif subcmd == "on?"
      exit_code = Term::ANSIColor::coloring? ? 0 : 1
    elsif subcmd == "off?"
      exit_code = Term::ANSIColor::coloring? ? 1 : 0
    else
      puts optparse
      return 127
    end
    unless options[:quiet]
      if Term::ANSIColor::coloring?
        puts "#{cyan}coloring: #{bold}#{green}on#{reset}"
      else
        puts "coloring: off"
      end
    end
    return exit_code
  end

end
