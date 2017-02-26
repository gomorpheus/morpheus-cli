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
  register_subcommands :add, :remove, :list
  #set_default_subcommand :add

  def initialize() 
  end

  def usage
    out = "Usage: morpheus #{command_name} [alias]=[command string]"
    out
  end

  def handle(args)
    if args.empty?
      puts usage
      exit 127
    elsif self.class.has_subcommand?(args[0])
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = usage
      #build_common_options(opts, options, [])
      opts.on('-h', '--help', "Prints this help" ) do
        puts opts.banner
        puts "Commands:"
        subcommands.sort.each {|cmd, method|
            puts "\t#{cmd.to_s}"
          }
        puts "This defines an alias of a command.\n" + 
              "Aliases are preserved for future use in your config.\n" + 
              "You can simply use 'alias' instead of 'alias add'"
        exit
      end
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end

    alias_definition = args[0]
    alias_name, command_string = Morpheus::Cli::CliRegistry.parse_alias_definition(alias_definition)

    if alias_name.empty? || command_string.empty?
      print_red_alert "invalid alias syntax: #{alias_definition}"
      exit 1
    else
      # config[:aliases] ||= []
      # config[:aliases] << {name: alias_name, command: command_string}
      Morpheus::Cli::CliRegistry.instance.add_alias(alias_name, command_string)
      Morpheus::Cli::ConfigFile.instance.save_file()
      #puts "registered alias #{alias_name}='#{command_string}'"
      #print "registered alias '#{alias_name}'", "\n"
    end

    Morpheus::Cli::Shell.instance.recalculate_auto_complete_commands()

  end
  
  def remove(args)
    options = {}
    do_remove = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[alias1] [alias2]")
      build_common_options(opts, options, [])
      opts.footer = "This is how you remove alias definitions from your config."
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
    options = {format:'friendly', sort:'name'}
    do_remove = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      opts.on( '-E', '--export', "Output the aliases just as they would appear in your .morpheusrc config file." ) do
        options[:format] = 'export'
      end
      build_common_options(opts, options, [:list, :json])
      opts.footer = "This outputs a list of your defined aliases."
    end
    optparse.parse!(args)

    #my_aliases = Morpheus::Cli::CliRegistry.all_aliases
    my_aliases = Morpheus::Cli::CliRegistry.all_aliases.collect {|k,v|
      {name: k, command_string: v}
    }

    # todo: generic support :list options on a local Array
    if options[:phrase]
      # my_aliases = my_aliases.grep(/^#{Regexp.escape(options[:phrase])}/)
      match_regex = /#{Regexp.escape(options[:phrase])}/
      my_aliases = my_aliases.select {|it| 
        it[:name].to_s =~ match_regex || it[:command_string].to_s =~ match_regex
      }
    end

    options[:sort] ||= 'name'
    options[:direction] ||= 'asc'

    if options[:sort]
      if options[:sort].to_s == 'name'
        my_aliases = my_aliases.sort {|x,y| x[:name].to_s.downcase <=> y[:name].to_s.downcase }
      elsif options[:sort].to_s == 'ts'
        # just relies on the order they were registered in, heh...
        my_aliases = my_aliases.sort {|x,y| x[:command_string].to_s.downcase <=> y[:command_string].to_s.downcase }
      else
        # a-z is the default, and the best
      end
    end

    if options[:direction] == 'desc'
      my_aliases = my_aliases.reverse
    end
    if options[:offset]
      my_aliases = my_aliases.slice(options[:offset].to_i, my_aliases.size)
    end
    if options[:max]
      my_aliases = my_aliases.first(options[:max].to_i)
    end
    num_aliases = my_aliases.size
    out = ""
    if options[:json]
      options[:format] = 'json'
    end
    if options[:format] == 'json' || options[:json]
      alias_json = {}
      my_aliases.each do |it|
        alias_json[it[:name]] = it[:command_string]
      end
      out << JSON.pretty_generate({aliases: alias_json})
      out << "\n"
    elsif options[:format] == 'export' || options[:format] == 'config'
      # out << "# morpheus aliases for #{`whoami`}\n" # windows!
      out << "# morpheus aliases\n"
      my_aliases.each do |it|
        out <<  "#{it[:name]}='#{it[:command_string]}'"
        out << "\n"
      end
    else 
      # friendly
      #out << cyan
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
      out << reset
      my_aliases.each do |it|
        out <<  "\t#{cyan}#{it[:name]}#{reset}='#{it[:command_string]}'"
        out << "\n"
      end
      out << reset
    end
    print out
  end

end
