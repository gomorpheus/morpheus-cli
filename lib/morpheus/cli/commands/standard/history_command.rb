require 'optparse'
require 'json'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::HistoryCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'history'
  set_command_hidden

  # todo: support all the other :list options too, not just max
  # AND start logging every terminal command, not just shell...
  def handle(args)
    options = {show_pagination:false}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name}"
      # -n is a hidden alias for -m
      opts.on( '-n', '--max-commands MAX', "Alias for -m, --max option." ) do |val|
        options[:max] = val
      end
      opts.add_hidden_option('-n')
      opts.on( '-p', '--pagination', "Display pagination and count info eg. Viewing 1-M of N" ) do
        options[:show_pagination] = true
      end
      opts.on( nil, '--flush', "Flush history, purges entire shell history file." ) do
        options[:do_flush] = true
      end
      build_common_options(opts, options, [:list, :auto_confirm])
      opts.footer = <<-EOT
Print command history.
The --flush option can be used to purge the history.

Examples: 
    history
    history -m 100
    history --flush

The most recently executed commands are seen by default.  Use --reverse to see the oldest commands.
EOT
    end
    raw_cmd = "#{command_name} #{args.join(' ')}"
    optparse.parse!(args)
    verify_args!(args:args, count: 0, optparse:optparse)
    if options[:do_flush]
      command_count = Morpheus::Cli::Shell.instance.history_commands_count
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to flush your command history (#{format_number(command_count)} #{command_count == 1 ? 'command' : 'commands'})?")
        return 9, "aborted command"
      end
      flush_n = options[:max] ? options[:max] : nil
      Morpheus::Cli::Shell.instance.flush_history(flush_n)
      return 0
    else
      Morpheus::Cli::Shell.instance.print_history(options)
      return 0  
    end
  end

end
