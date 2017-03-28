require 'optparse'
require 'json'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::SetPromptCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'set-prompt'
  set_command_hidden

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [shell-prompt]"
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
        puts opts
        exit
      end
      opts.footer = <<-EOT
This is intended for use in your morpheus scripts.
It allows you to set the shell prompt.
This can be used as alternative to setting the MORPHEUS_PS1 environment variable

Examples: 
    set-prompt "morph> "
    set-prompt "%cyanmorpheus> "
    set-prompt "[%magenta%remote%reset] %cyan%username morpheus> "

The default prompt is: "%cyanmorpheus> "

EOT
    end
    optparse.parse!(args)

    if args.count != 1
      $stderr.puts Morpheus::Terminal.angry_prompt
      $stderr.puts "too many arguments"
      $stderr.puts optparse
      return false
    end
    
    Morpheus::Terminal.instance.prompt = args[0]
    #Morpheus::Shell.instance.prompt = args[0]
    Morpheus::Shell.instance.recalculate_prompt()
    

    return true
  end

end
