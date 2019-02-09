require 'morpheus/cli/cli_command'

# This is for printing the content of files(s)
class Morpheus::Cli::CatCommand
  include Morpheus::Cli::CliCommand
  set_command_name :cat
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name} [file] [file2]"
      build_common_options(opts, options, [])
      opts.footer = "This will execute a file, treatin it as a script of morpheus commands"
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end

    arg_files = args
    arg_files.each do |arg_file|
      arg_file = File.expand_path(arg_file)
      if !File.exists?(arg_file)
        print_red_alert "morpheus cat: file not found: '#{arg_file}'"
        return 1
      end
      if File.directory?(arg_file)
        print_red_alert "morpheus cat: file is a directory: '#{arg_file}'"
        return 1
      end
      file_contents = File.read(arg_file)
      print file_contents.to_s
      return 0
    end
    return true
  end

end
