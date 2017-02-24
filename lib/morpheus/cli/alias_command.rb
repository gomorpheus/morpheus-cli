require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/shell'
require 'json'

# This command allows the creation of an alias
# these aliases are stored in the $MORPHEUS_CLI_HOME/.morpheusrc
# See Morpheus::Cli::ConfigFile
#
class Morpheus::Cli::AliasCommand
  include Morpheus::Cli::CliCommand
  
  set_command_name :alias
  set_command_hidden # maybe remove this...

  register_subcommands :add, :remove, :list
  #set_default_subcommand :add

  def initialize() 
    
  end

  def usage
    out = "Usage: morpheus #{command_name} [alias]=[command string]"
    out
  end

  def handle(args)
    if self.class.has_subcommand?(args[0])
      handle_subcommand(args)
    elsif args.count == 1
      add(args)
    else
      handle_subcommand(args)
      #list([])
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
    # puts "debug: alias_definition is #{alias_definition}"
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
      #puts "registered alias #{alias_name}='#{command_string}'"
      print "registered alias '#{alias_name}'", "\n"
    end

    Morpheus::Cli::Shell.instance.recalculate_auto_complete_commands()

  end
  
  def remove(args)
    options = {}
    do_remove = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[alias1] [alias2]")
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    
    if args.count < 1
      puts optparse
      exit 1
    end
    
    alias_names = args
    
    alias_names.each do |arg|
      if !Morpheus::Cli::CliRegistry.has_alias?(arg)
        print_red_alert "alias not found by name '#{arg}'"
        exit 1
      end
    end

    alias_names.each do |arg|
      Morpheus::Cli::CliRegistry.instance.remove_alias(arg)
    end

    Morpheus::Cli::ConfigFile.instance.save_file()
    if args.count == 1
      puts "removed alias '#{alias_names[0]}'"
    else
      puts "removed aliases '#{alias_names.join(', ')}'"
    end
  end

  def list(args)
    options = {}
    do_remove = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)

    my_aliases = Morpheus::Cli::CliRegistry.all_aliases
    if options[:phrase]
      # my_aliases = my_aliases.grep(/^#{Regexp.escape(options[:phrase])}/)
      match_regex = /#{Regexp.escape(options[:phrase])}/
      my_aliases = my_aliases.select {|k,v| 
        k.to_s =~ match_regex || v.to_s =~ match_regex
      }
    end
    num_aliases = my_aliases.keys.size
    out = ""
    if num_aliases == 0
      #print "You have #{num_aliases} aliases defined."
      out << "Found #{num_aliases} aliases"
    elsif num_aliases == 1
      #print "You have just one alias defined."
      out <<  "Found #{num_aliases} alias"
    else
      #print "You have #{num_aliases} aliases defined."
      out <<  "Found #{num_aliases} aliases"
    end
    if options[:phrase]
      out << " matching '#{options[:phrase]}'"
    end
    out <<  "\n"
    if num_aliases > 0
      out << "\n# aliases:\n\n"
    end
    # todo: store these in config file sorted too?
    my_aliases.keys.sort.each {|alias_name|
      cmd = Morpheus::Cli::CliRegistry.instance.get_alias(alias_name)
      out <<  "#{alias_name}='#{cmd}'"
      out << "\n"
    }

    out <<  "\n"
    print out
  end

end
