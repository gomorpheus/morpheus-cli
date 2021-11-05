require 'morpheus/cli/cli_command'

# Command for editing the .morpheus_profile initialization script
class Morpheus::Cli::EditProfileCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'edit-profile'
  #set_command_hidden

  def handle(args)
    options = {}
    editor = ENV['EDITOR'] || 'nano'
    filename = Morpheus::Cli::DotFile.morpheus_profile_filename
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name}"
      opts.on( '-e', '--editor PROGRAM', "Editor program to use. The default is $EDITOR." ) do |val|
        editor = val
      end
      build_common_options(opts, options, [])
      opts.footer = <<-EOT
Edit your .morpheus_profile script located in the morpheus home directory.
This script runs whenever the morpheus terminal command is executed.
It provides a way to initialize your cli environment for all morpheus commands.

Example:

# disable coloring to exclude ansi characters in output
coloring off -q

# Enable debugging to print extra output for troubleshooting
debug on

EOT
    end
    optparse.parse!(args)

    if !editor
      print_error Morpheus::Terminal.angry_prompt
      puts_error "You have not defined an EDITOR."
      puts_error "Try export EDITOR=emacs"
      #puts "Trying nano..."
      #editor = "nano"
      return 1
    end
    puts "opening #{filename} for editing"
    system(editor, filename)
    if !$?.success?
      print_error Morpheus::Terminal.angry_prompt
      puts_error "edit command failed with #{$?.exitstatus}: #{editor} #{filename}"
      return $?.exitstatus
    end
    if Morpheus::Cli::Shell.has_instance?
      puts "use 'reload' to re-execute your startup script"
    end
    return 0 # $?
  end

end
