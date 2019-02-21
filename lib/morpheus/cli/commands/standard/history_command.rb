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
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name}"
      # opts.on( '-m', '--max MAX', "Max Results" ) do |max|
      #   options[:max] = max.to_i
      # end
      # opts.on( '-o', '--offset OFFSET', "Offset Results" ) do |offset|
      #   options[:offset] = offset.to_i.abs
      # end
      # opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
      #   options[:phrase] = phrase
      # end
      # opts.on( '-S', '--sort ORDER', "Sort Order" ) do |v|
      #   options[:sort] = v
      # end
      # opts.on( '-D', '--desc', "Reverse Sort Order" ) do |v|
      #   options[:direction] = "desc"
      # end
      opts.on( '-n', '--max-commands MAX', "Max Results. Default is 25" ) do |val|
        options[:max] = val
      end
      opts.add_hidden_option('-n')
      opts.on( nil, '--flush', "Flush history, purges entire shell history file." ) do |val|
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

EOT
    end
    raw_cmd = "#{command_name} #{args.join(' ')}"
    optparse.parse!(args)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if options[:do_flush]
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to flush your command history?")
        return 9, "aborted command"
      end
      Morpheus::Cli::Shell.instance.flush_history
      return 0
    else
      max_commands = options[:max] || 25
      Morpheus::Cli::Shell.instance.print_history(max_commands)
      last_cmd = Morpheus::Cli::Shell.instance.last_command
      # log history, but not consecutive log entries
      if last_cmd.nil? || last_cmd[:command] != raw_cmd
        Morpheus::Cli::Shell.instance.log_history_command(raw_cmd)
      end
      return 0  
    end
  end

end
