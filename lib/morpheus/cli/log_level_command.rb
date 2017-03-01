require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

class Morpheus::Cli::LogLevelCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'log-level' # :log_level
  set_command_hidden

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [debug|info|0|1]"
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
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
    if ["debug", "0"].include?(args[0].to_s.strip.downcase)
      Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      ::RestClient.log = Morpheus::Logging.debug? ? STDOUT : nil
    elsif ["info", "1"].include?(args[0].to_s.strip.downcase)
      Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
      ::RestClient.log = Morpheus::Logging.debug? ? STDOUT : nil
    elsif args[0].to_i < 6
      Morpheus::Logging.set_log_level(args[0].to_i)
      ::RestClient.log = Morpheus::Logging.debug? ? STDOUT : nil
    else
      puts optparse
      return false
    end
    return true
  end

end
