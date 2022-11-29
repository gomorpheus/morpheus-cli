require 'morpheus/cli/cli_command'

# This is for use in dotfile scripts and the shell..
class Morpheus::Cli::SourceCommand
  include Morpheus::Cli::CliCommand
  set_command_name :source
  set_command_hidden

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [file] [file2]"
      build_common_options(opts, options, [])
      opts.footer = "This will execute a file as a script where each line is a morpheus command or expression."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    exit_code, err = 0, nil
    source_files = args
    bad_files = source_files.select { |source_file| !File.exist?(File.expand_path(source_file)) }
    if !bad_files.empty?
      raise_command_error("source file(s) not found: #{bad_files.join(', ')}")
    end
    source_files.each do |source_file|
      Morpheus::Cli::DotFile.new(File.expand_path(source_file)).execute()
    end
    return exit_code, err
  end

end
