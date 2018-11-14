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
      opts.banner = "Usage: morpheus #{command_name} [on|off]"
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
      opts.footer = "Enable [on] or Disable [off] ANSI Colors for all output."
    end
    optparse.parse!(args)
    if args.count > 1
      puts optparse
      exit 1
    end
    if args.count == 1
      is_on = ["on","true", "1"].include?(args[0].to_s.strip.downcase)
      is_off = ["off","false", "0"].include?(args[0].to_s.strip.downcase)
      if !is_on && !is_off
        puts optparse
        exit 1
      end
      Term::ANSIColor::coloring = is_on
    end
    if Term::ANSIColor::coloring?
      puts "#{cyan}coloring is #{bold}#{green}on#{reset}"
    else
      puts "coloring is off"
    end
  end

end
