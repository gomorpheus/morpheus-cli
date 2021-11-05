require 'morpheus/cli/cli_command'

class Morpheus::Cli::LogLevelCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'log-level' # :log_level
  set_command_hidden

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [debug|info|0|1]"
      #build_common_options(opts, options, [])
      opts.on('-q','--quiet', "No Output, do not print to stdout") do
        options[:quiet] = true
      end
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      opts.footer = <<-EOT
This is intended for use in your morpheus scripts.
It allows you to set the global logging level.
The only available levels right now are debug [0] and info [1].
The default is info [1].
EOT
    end
    optparse.parse!(args)
    if args.count == 0
      puts "#{Morpheus::Logging.log_level}"
      return true
    end
    if args.count > 1
      puts optparse
      return false
    end
    debug_was_enabled = Morpheus::Logging.debug?
    if ["debug", "0"].include?(args[0].to_s.strip.downcase)
      Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      Morpheus::Logging::DarkPrinter.puts "debug enabled" unless debug_was_enabled
    elsif ["info", "1"].include?(args[0].to_s.strip.downcase)
      Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::INFO)
      ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
    elsif args[0].to_i < 6
      Morpheus::Logging.set_log_level(args[0].to_i)
      ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
    else
      puts optparse
      return false
    end
    return true
  end

end
