require 'morpheus/cli/cli_command'
require 'term/ansicolor'
require 'json'

# Utility command for exiting a shell
class Morpheus::Cli::ExitCommand
  include Morpheus::Cli::CliCommand
  
  set_command_name :'exit'
  
  set_command_hidden

  def handle(args)
    exit_code = 0
    options = {}
    filename = Morpheus::Cli::DotFile.morpheus_profile_filename
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: exit [code]"
      build_common_options(opts, options, [])
      opts.footer = "Exit morpheus . Default is 0"
    end
    optparse.parse!(args)
    
    if args[0]
      exit_code = args[0].to_i
    end

    if options[:debug]
      puts "#{dark}exit #{exit_code}#{reset}"
    end

    exit exit_code

  end

end
