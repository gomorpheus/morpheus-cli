require 'morpheus/cli/cli_command'

# This is for use in dotfile scripts and the shell..
class Morpheus::Cli::SourceCommand
  include Morpheus::Cli::CliCommand
  set_command_name :source
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [file] [file2]"
      build_common_options(opts, options, [])
      opts.footer = "This will execute a file as a script where each line is a morpheus command or expression."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return false # exit 1
    end

    source_files = args
    source_files.each do |source_file|
      # execute a source script
      source_file = File.expand_path(source_file)
      if File.exists?(source_file)
        cmd_results = Morpheus::Cli::DotFile.new(source_file).execute()
      else
        print_red_alert "file not found: '#{source_file}'"
        # return false
      end
    end

    return true
  end

end
