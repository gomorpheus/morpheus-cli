require 'morpheus/cli/cli_command'
require 'term/ansicolor'
require 'json'

# This is for use in dotfile scripts
class Morpheus::Cli::Sleep
  include Morpheus::Cli::CliCommand
  set_command_name :sleep
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus sleep [seconds]"
      build_common_options(opts, options, [:quiet])
    end
    optparse.parse!(args)
    
    sleep_seconds = args[0]
    
    # if !sleep_seconds
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "#{command_name} missing argument: [seconds]\n#{optparse}"
    #   return 1
    # end

    if !sleep_seconds
      sleep_seconds = 1.0
    end

    # do it
    if !options[:quiet]
      if options[:debug]
        # puts "Sleep for #{sleep_seconds.to_f} seconds..."
        Morpheus::Logging::DarkPrinter.puts "sleep #{sleep_seconds.to_f} seconds..." if Morpheus::Logging.debug?
      end
    end

    sleep(sleep_seconds.to_f)
    
    return 0
  end

end
