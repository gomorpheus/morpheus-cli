require 'morpheus/cli/cli_command'
require 'morpheus/logging'

# This is for use in dotfile scripts
# It allows you to turn colors on or off globally
class Morpheus::Cli::DebugCommand
  include Morpheus::Cli::CliCommand
  set_command_name :debug
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [on|off]"
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      opts.footer = "Enable [on] or Disable [off] debugging for all output.\n" + 
                    "Use [on?] or [off?] to print the current value and exit accordingly." + "\n" +
                    "Pass no arguments to just print the current value."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    
    exit_code = 0

    if args.count == 0
      # just print
    else
      subcmd = args[0].to_s.strip
      if subcmd == "on"
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      elsif subcmd == "off"
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::INFO)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      elsif subcmd == "on?"
        exit_code = Morpheus::Logging.debug? ? 0 : 1
      elsif subcmd == "off?"
        exit_code = Morpheus::Logging.debug? ? 1 : 0
      else
        puts optparse
        return 127
      end
    end
    unless options[:quiet]
      if Morpheus::Logging.debug?
        puts "#{cyan}debug: #{green}on#{reset}"
      else
        puts "#{cyan}debug: #{dark}off#{reset}"
      end
    end
    return exit_code
  end

end
