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
      opts.banner = "Usage: morpheus #{command_name} [file ...]"
      build_common_options(opts, options, [])
      opts.footer = "Concatenate and print files." + "\n" +
                    "[file] is required. This is the name of a file. Supports many [file] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} expects 1-N arguments and received #{args.count} #{args}\n#{optparse}"
      return 1
    end

    arg_files = args
    arg_files.each do |arg_file|
      arg_file = File.expand_path(arg_file)
      if !File.exist?(arg_file)
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "#{command_name}:  file not found: '#{arg_file}'"
        #print_red_alert "morpheus cat: file not found: '#{arg_file}'"
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
