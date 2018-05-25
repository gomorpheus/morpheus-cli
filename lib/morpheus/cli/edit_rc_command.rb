require 'morpheus/cli/cli_command'
require 'term/ansicolor'
require 'json'

# Command for editing the .morpheus_profile initalization script
class Morpheus::Cli::EditRcCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'edit-rc'
  #set_command_hidden

  def handle(args)
    options = {}
    editor = nil
    filename = Morpheus::Cli::DotFile.morpheusrc_filename
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus #{command_name}"
      opts.on( '-e', '--editor PROGRAM', "Editor program to use. The default is $EDITOR." ) do |val|
        editor = val.gsub("'",'')
      end
      build_common_options(opts, options, [])
      opts.footer = "Edit your morpheus initialization script at #{filename}"
    end
    optparse.parse!(args)
    

    if !editor
      editor = ENV['EDITOR']
    end

    # try something...
    if !editor
      if Morpheus::Cli.windows?
        editor = "notepad"
      else
        editor = "nano"
      end
    end

    if !editor
      print_error Morpheus::Terminal.angry_prompt
      puts_error "You have not defined an EDITOR."
      puts_error "Try export EDITOR=emacs"
      #puts "Trying nano..."
      #editor = "nano"
      return 1
    end
    has_editor = true
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
