require 'morpheus/cli/cli_command'

class Morpheus::Cli::SetPromptCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'set-prompt'
  set_command_hidden

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [prompt]"
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      variable_map = Morpheus::Cli::Echo.variable_map
      formatted_variable_map = "    " + variable_map.keys.join(' ')
      opts.footer = <<-EOT
Customize your morpheus shell prompt.

[prompt] is required. This is the string the terminal prints when you interact with it.

Examples: 
    set-prompt "morpheus $ "
    set-prompt "%cyanmorpheus> "
    set-prompt "[%magenta%remote%reset] %cyan%username> "
    set-prompt "%green%username%reset@%remote %magenta> %reset"
    set-prompt "%cyan%username%reset@%magenta%remote %cyanmorpheus> %reset"

The available variables are:
#{formatted_variable_map}

The default prompt is: "%cyanmorpheus> %reset"
The value may also be set through the enviroment variable MORPHEUS_PS1.
EOT
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    # do it
    self.my_terminal.prompt = args[0]
    # Morpheus::Terminal.instance.prompt = args[0]
    Morpheus::Cli::Shell.instance.recalculate_prompt()
    Morpheus::Cli::Echo.recalculate_variable_map()
    return 0
  end

end
