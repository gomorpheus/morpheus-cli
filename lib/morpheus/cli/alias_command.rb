require 'optparse'
require 'morpheus/cli/cli_command'
require 'json'

# This command allows the creation of an alias
# these aliases are stored in the $MORPHEUS_CLI_HOME/.morpheusrc
# See Morpheus::Cli::ConfigFile
#
class Morpheus::Cli::AliasCommand
  include Morpheus::Cli::CliCommand
  
  set_command_name :alias
  set_command_hidden # maybe remove this...

  register_subcommands :add, :remove
  #set_default_subcommand :add

  def initialize() 
    
  end

  def usage
    out = "Usage: morpheus #{command_name} [alias]=[command string]"
    out
  end

  def handle(args)
    if args.count == 1
      add(args)
    else
      handle_subcommand(args)
    end
  end
  
  def add(args)

    options = {}
    do_remove = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('-r','--remove', "Remove the alias by name") do |val|
        do_remove = true
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    
    if do_remove
      return remove(args)
    end
    
    if args.count < 1
      puts optparse
      exit 1
    end

    alias_definition = args[0]

    alias_name, command_string = alias_definition.sub(/^alias\s+/, "").split('=')
    command_string = command_string.strip.sub(/^'/, "").sub(/'\Z/, "").strip
    if alias_name.empty? || command_string.empty?
      print_red_alert "invalid alias syntax: #{alias_definition}"
      exit 1
    else
      # config[:aliases] ||= []
      # config[:aliases] << {name: alias_name, command: command_string}
      Morpheus::Cli::CliRegistry.instance.add_alias(alias_name, command_string)
      Morpheus::Cli::ConfigFile.instance.save_file()
      puts "registered alias #{alias_name}='#{command_string}'"
    end


  end
  
  def remove(args)
    options = {}
    do_remove = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    
    if args.count < 1
      puts optparse
      exit 1
    end
    alias_name = args[0]

    if !Morpheus::Cli::CliRegistry.has_alias?(args[0])
      print_red_alert "alias not found by name '#{args[0]}'"
      exit 1
    end

    Morpheus::Cli::CliRegistry.instance.remove_alias(alias_name)
    Morpheus::Cli::ConfigFile.instance.save_file()
    puts "removed alias '#{alias_name}'"
  end

end
