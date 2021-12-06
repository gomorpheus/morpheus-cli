require 'morpheus/cli/cli_command'

# This is for opening a file
class Morpheus::Cli::OpenCommand
  include Morpheus::Cli::CliCommand
  set_command_name :open
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [file ...]"
      build_common_options(opts, options, [:dry_run])
      opts.footer = "Open file(s)." + "\n" +
                    "[file] is required. This is the name of a file. Supports many [file] arguments."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min: 1)
    open_args = args.join(" ")
    if options[:dry_run]
      print "\n"
      print "#{cyan}#{bold}#{dark}SYSTEM COMMAND#{reset}\n"
      puts Morpheus::Util.open_url_command(open_args)
      return 0, nil
    end
    return Morpheus::Util.open_url(open_args)
  end

end
