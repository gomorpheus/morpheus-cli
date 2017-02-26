require 'fileutils'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'


class Morpheus::Cli::Remote
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :add, :remove, :use, :unuse, :current => :print_current
  set_default_subcommand :list

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def handle(args)
    if args.count == 0
      list(args)
    else
      handle_subcommand(args)
    end
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [])
      opts.footer = "This outputs a list of the remote appliances.\n" + 
                    "It also displays the current active appliance.\n" + 
                    "The shortcut `remote` can be used instead of `remote list`."
    end
    optparse.parse!(args)
    @appliances = ::Morpheus::Cli::Remote.appliances
    if @appliances == nil || @appliances.empty?
      print yellow,"No remote appliances configured, see `remote add`",reset,"\n"
    else
      rows = @appliances.collect do |app_name, v|
        {
          active: (v[:active] ? "=>" : ""),
          name: app_name,
          host: v[:host]
        }
      end
      print "\n" ,cyan, bold, "Morpheus Appliances\n","==================", reset, "\n\n"
      print cyan
      tp rows, {:active => {:display_name => ""}}, {:name => {:width => 16}}, {:host => {:width => 40}}
      print reset
      if @appliance_name
        #unless @appliances.keys.size == 1
          print cyan, "\n# => Currently using #{@appliance_name}\n", reset
        #end
      else
        print "\n# => No active remote appliance, see `remote use`\n", reset
      end
      print "\n" # meh
    end
  end

  def add(args)
    options = {}
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [url]")
      build_common_options(opts, options, [])
      opts.on( '--use', '--use', "Make this the current remote appliance" ) do
        use_it = true
      end
      # let's free up the -d switch for global options, maybe?
      opts.on( '-d', '--default', "Does the same thing as --use" ) do
        use_it = true
      end
      # todo: use Morpheus::Cli::OptionParser < OptionParser
      # opts.on('-h', '--help', "Prints this help" ) do
      #   hidden_switches = ["--default"]
      #   good_opts = opts.to_s.split("\n").delete_if { |line| hidden_switches.find {|it| line =~ /#{Regexp.escape(it)}/ } }.join("\n") 
      #   puts good_opts
      #   exit
      # end
      opts.footer = "This will add a new appliance to your list.\n" + 
                    "If it's first one, it will be made the current active appliance."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    
    new_appliance_name = args[0].to_sym
    url = args[1]
    if url !~ /^https?\:\/\//
      print red, "The specified appliance url is invalid: '#{args[1]}'", reset, "\n"
      puts optparse
      exit 1
    end
    # maybe a ping here would be cool
    @appliances = ::Morpheus::Cli::Remote.appliances
    if @appliances.keys.empty?
      use_it = true
    end
    if @appliances[new_appliance_name] != nil
      print red, "Remote appliance already configured with the name '#{args[0]}'", reset, "\n"
    else
      @appliances[new_appliance_name] = {
        host: url,
        active: use_it
      }
      ::Morpheus::Cli::Remote.save_appliances(@appliances)
      if use_it
        #Morpheus::Cli::Remote.set_active_appliance(new_appliance_name)
        @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
      end
    end
    #list([])
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-d', '--default', "Make this the default remote appliance" ) do
        options[:default] = true
      end
      opts.footer = "This will delete an appliance from your list."
      build_common_options(opts, options, [:auto_confirm])
    end
    optparse.parse!(args)
    if args.empty?
      puts optparse
      exit 1
    end
    @appliances = ::Morpheus::Cli::Remote.appliances
    appliance_name = args[0].to_sym
    if @appliances[appliance_name] == nil
      print red, "Remote appliance not found by the name '#{args[0]}'", reset, "\n"
    else
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove this remote appliance '#{appliance_name}'?", options)
        exit 1
      end
      @appliances.delete(appliance_name)
      ::Morpheus::Cli::Remote.save_appliances(@appliances)
      # todo: also delete credentials and groups[appliance_name]
      ::Morpheus::Cli::Groups.clear_active_group(appliance_name) # rescue nil
      # this should be a class method too
      #::Morpheus::Cli::Credentials.clear_saved_credentials(appliance_name)
      ::Morpheus::Cli::Credentials.new(appliance_name, nil).clear_saved_credentials(appliance_name) # rescue nil
      #list([])
    end
  end

  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [])
      opts.footer = "This allows you to switch between your different appliances."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    new_appliance_name = args[0].to_sym
    @appliances = ::Morpheus::Cli::Remote.appliances
    if @appliance_name && @appliance_name.to_s == new_appliance_name.to_s
      print reset,"Already using the appliance '#{args[0]}'","\n",reset
    else
      if @appliances[new_appliance_name] == nil
        print red, "Remote appliance not found by the name '#{args[0]}'", reset, "\n"
      else
        Morpheus::Cli::Remote.set_active_appliance(new_appliance_name)
        @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
        #print cyan,"Switched to using appliance #{args[0]}","\n",reset
        #list([])
      end
    end
  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "This will switch to no active appliance.\n" +
        "You will need to use an appliance again, or pass the --remote option to your commands..\n"
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    if @appliance_name
      Morpheus::Cli::Remote.clear_active_appliance()
      @appliance_name, @appliance_url = nil, nil
      return true
    else
      puts "You are not using any appliance"
      return false
    end
  end

  def print_current(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)

    if @appliance_name
      print cyan, @appliance_name,"\n",reset
    else
      print yellow, "No active appliance, see `remote use`\n", reset
    end
  end

  class << self
    include Term::ANSIColor

    # for caching the the contents of YAML file $home/appliances
    # it is structured like :appliance_name => {:host => "htt[://api.gomorpheus.com", :active => true}
    # not named @@appliances to avoid confusion with the instance variable . This is also a command class...
    @@appliance_config = nil 
    #@@current_appliance = nil



    def appliances
      self.appliance_config
    end

    def appliance_config
      @@appliance_config ||= load_appliance_file || {}
    end

    # Returns two things, the remote appliance name and url
    def active_appliance
      if self.appliances.empty?
        return nil, nil
      end
      app_name, app_map = self.appliances.find {|k,v| v[:active] == true }
      if app_name
        return app_name, app_map[:host]
      else
        return app_name, nil
      end
    end

    def set_active_appliance(name)
      new_appliances = self.appliances
      new_appliances.each do |k,v|
        is_match = (name ? (k == name.to_sym) : false)
        if is_match
          v[:active] = true
        else
          v[:active] = false
        end
      end
      save_appliances(new_appliances)
    end

    def clear_active_appliance
      new_appliances = self.appliances
      new_appliances.each do |k,v|
        v[:active] = false
      end
      save_appliances(new_appliances)
    end

    def load_appliance_file
      fn = appliances_file_path
      if File.exist? fn
        print "#{dark} #=> loading appliances file #{fn}#{reset}\n" if Morpheus::Logging.debug?
        return YAML.load_file(fn)
      else
        return {}
        # return {
        #   morpheus: {
        #     host: 'https://api.gomorpheus.com',
        #     active: true
        #   }
        # }
      end
    end

    def appliances_file_path
      File.join(Morpheus::Cli.home_directory,"appliances")
    end

    def save_appliances(new_config)
      File.open(appliances_file_path, 'w') {|f| f.write new_config.to_yaml } #Store
      FileUtils.chmod(0600, appliances_file_path)
      #@@appliance_config = load_appliance_file
      @@appliance_config = new_config
    end

  end

end
