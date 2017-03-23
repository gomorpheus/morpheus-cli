require 'fileutils'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'


class Morpheus::Cli::Remote
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :add, :get, :remove, :use, :unuse, {:current => :print_current}, :setup
  set_default_subcommand :list

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def handle(args)
    # if args.count == 0
    #   list(args)
    # else
    #   handle_subcommand(args)
    # end
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [])
      opts.footer = "This outputs a list of the configured remote appliances."
    end
    optparse.parse!(args)
    @appliances = ::Morpheus::Cli::Remote.appliances
    if @appliances.empty?
      raise_command_error "You have no appliances configured. See the `remote add` command."
    else
      rows = @appliances.collect do |app_name, v|
        {
          active: (v[:active] ? "=>" : ""),
          name: app_name,
          host: v[:host]
        }
      end
      print_h1 "Morpheus Appliances"
      print cyan
      tp rows, {:active => {:display_name => ""}}, {:name => {:width => 16}}, {:host => {:width => 40}}
      print reset
      if @appliance_name
        #unless @appliances.keys.size == 1
          print cyan, "\n# => Currently using #{@appliance_name}\n", reset
        #end
      else
        print "\n# => No current active appliance, see `remote use`\n", reset
      end
      print "\n" # meh
    end
  end

  def add(args)
    options = {}
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [url]")
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
      build_common_options(opts, options, [:quiet])
      opts.footer = "This will add a new appliance to your list.\n" + 
                    "If it's first one, it will be made the current active appliance."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    
    new_appliance_name = args[0].to_sym
    if new_appliance_name == :current
      print red, "The specified appliance name is invalid: '#{args[0]}'", reset, "\n"
      #puts optparse
      exit 1
    end
    url = args[1]
    if url !~ /^https?\:\/\//
      print red, "The specified appliance url is invalid: '#{args[1]}'", reset, "\n"
      #puts optparse
      exit 1
    end
    # maybe a ping here would be cool
    @appliances = ::Morpheus::Cli::Remote.appliances
    if @appliances.keys.empty?
      use_it = true
    end
    if @appliances[new_appliance_name] != nil
      print red, "Remote appliance already configured with the name '#{args[0]}'", reset, "\n"
      return false
    else
      @appliances[new_appliance_name] = {
        host: url,
        active: use_it
      }
      ::Morpheus::Cli::Remote.save_appliances(@appliances)
      if use_it
        Morpheus::Cli::Remote.set_active_appliance(new_appliance_name)
        @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
      end
    end
    
    if options[:quiet] || options[:no_prompt]
      return true
    end
    
    # check to see if this is a fresh appliance. 
    # GET /api/setup only returns 200 if it can still be initialized, else 400
    @setup_interface = Morpheus::SetupInterface.new(@appliance_url)
    appliance_status_json = nil
    begin
      appliance_status_json = @setup_interface.get()
      if appliance_status_json['success'] == true
        return setup([new_appliance_name])
      end
      # should not get here
    rescue RestClient::Exception => e
      #print_rest_exception(e, options)
      # laff, treating any non - 200 as meaning it is good ...is bad.. could be at the wrong site.. sending credentials..
      print cyan,"Appliance is ready.\n", reset
    end

    if use_it
      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to login now?", options.merge({default: true}))
        return ::Morpheus::Cli::Login.new.handle([new_appliance_name])
      end
    end

    return true
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.footer = "View details about a remote appliance."
      build_common_options(opts, options, [:auto_confirm])
    end
    optparse.parse!(args)
    if args.empty?
      puts optparse
      exit 1
    end
    @appliances = ::Morpheus::Cli::Remote.appliances
    appliance_name = args[0].to_sym
    appliance = @appliances[appliance_name]
    if appliance == nil
      print red, "Remote appliance not found by the name '#{args[0]}'", reset, "\n"
    else
      print_h1 "Morpheus Appliance"

      puts as_description_list(appliance, [
        {"Name" => lambda {|i| appliance_name } },
        {"Url" => :host},
        {"Version" => :buildVersion},
        # {"Active" => :active},
      ])

      is_active = !!appliance[:active]
      if is_active
        puts "\n => This is the active appliance."
      end
      print reset,"\n"
    end
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
      opts.footer = "This sets the current active appliance.\n" +
                    "This allows you to switch between your different appliances.\n" + 
                    "You may override this with the --remote option in your commands."
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
        return false
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
        "This clears the current active appliance.\n" +
        "You will need to use an appliance, or pass the --remote option to your commands."
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
      build_common_options(opts, options, [:json])
      opts.footer = "Prints the name of the current remote appliance"
    end
    optparse.parse!(args)

    if @appliance_name
      print cyan, @appliance_name,"\n",reset
    else
      print yellow, "No active appliance, see `remote use`\n", reset
      return false
    end
  end

  # this is a wizard that walks through the /api/setup controller
  # it only needs to be used once to initialize a new appliance
  def setup(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "This can be used to initialize a new appliance.\n" + 
                    "You will be prompted to create the master account.\n" + 
                    "This is only available on a new, freshly installed, remote appliance."
    end
    optparse.parse!(args)

    if !@appliance_name
      print yellow, "No active appliance, see `remote use`\n", reset
      return false
    end

    # this works without any authentication!
    # it will allow anyone to use it, if there are no users/accounts in the system.
    #@api_client = establish_remote_appliance_connection(options)
    #@setup_interface = @api_client.setup
    @setup_interface = Morpheus::SetupInterface.new(@appliance_url)
    appliance_status_json = nil
    begin
      appliance_status_json = @setup_interface.get()
      if appliance_status_json['success'] != true
        print red, "Setup not available for appliance #{@appliance_name} - #{@appliance_url}.\n", reset
        print red, "#{appliance_status_json['msg']}\n", reset
        return false
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end
    
    payload = {}

    if appliance_status_json['hubRegistrationEnabled']
      link = File.join(@appliance_url, '/setup')
      print red, "Sorry, setup with hub registration is not yet available.\n", reset
      print "You can use the UI to setup your appliance.\n"
      print "Go to #{link}\n", reset
      # if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      #   system "start #{link}"
      # elsif RbConfig::CONFIG['host_os'] =~ /darwin/
      #   system "open #{link}"
      # elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
      #   system "xdg-open #{link}"
      # end
      return false
    else
      print_h1 "Morpheus Appliance Setup"

      puts "It looks like you're the first one here."
      puts "Let's initialize your remote appliance at #{@appliance_url}"


      
      # Master Account
      print_h2 "Create Master Account"
      account_option_types = [
        {'fieldName' => 'accountName', 'fieldLabel' => 'Master Account Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(account_option_types, options[:options])
      payload.merge!(v_prompt)

      # Master User
      print_h2 "Create Master User"
      user_option_types = [
        {'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
        {'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
        {'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
        {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'displayOrder' => 4},
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(user_option_types, options[:options])
      payload.merge!(v_prompt)

      # Password prompt with re-prompting if no match
      password_option_types = [
        {'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'displayOrder' => 6},
        {'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'displayOrder' => 7},
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(password_option_types, options[:options])
      while v_prompt['passwordConfirmation'] != v_prompt['password']
        print red, "Password confirmation does not match. Re-enter your new password.", reset, "\n"
        v_prompt = Morpheus::Cli::OptionTypes.prompt(password_option_types, options[:options])
      end
      payload.merge!(v_prompt)

      # Extra settings
      print_h2 "Initial Setup"
      extra_option_types = [
        {'fieldName' => 'applianceName', 'fieldLabel' => 'Appliance Name', 'type' => 'text', 'required' => true, 'defaultValue' => nil},
        {'fieldName' => 'applianceUrl', 'fieldLabel' => 'Appliance URL', 'type' => 'text', 'required' => true, 'defaultValue' => appliance_status_json['applianceUrl']},
        {'fieldName' => 'backups', 'fieldLabel' => 'Enable Backups', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'off'},
        {'fieldName' => 'monitoring', 'fieldLabel' => 'Enable Monitoring', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'on'},
        {'fieldName' => 'logs', 'fieldLabel' => 'Enable Logs', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'on'}
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(extra_option_types, options[:options])
      payload.merge!(v_prompt)

      begin
        if options[:dry_run]
          print_dry_run @setup_interface.dry.init(payload)
          return
        end
        if !options[:json]
          print "Initializing the appliance...\n"
        end
        json_response = @setup_interface.init(payload)
      rescue RestClient::Exception => e
        print_rest_exception(e, options)
        return false
      end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      print "\n"
      print cyan, "You have successfully setup the appliance.\n"
      #print cyan, "You may now login with the command `login`.\n"
      # uh, just use Credentials.login(username, password, {save: true})
      cmd_res = Morpheus::Cli::Login.new.login(['--username', payload['username'], '--password', payload['password'], '-q'])
      # print "\n"
      print cyan, "You are now logged in as the System Admin #{payload['username']}.\n"
      print reset
      #print "\n"

      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to apply your License Key now?", options.merge({:default => true}))
        cmd_res = Morpheus::Cli::License.new.apply([])
        # license_is_valid = cmd_res != false
      end

      if ::Morpheus::Cli::OptionTypes::confirm("Do you want to create the first group now?", options.merge({:default => true}))
        cmd_res = Morpheus::Cli::Groups.new.add(['--use'])

        #print "\n"

        # if cmd_res !=
          if ::Morpheus::Cli::OptionTypes::confirm("Do you want to create the first cloud now?", options.merge({:default => true}))
            cmd_res = Morpheus::Cli::Clouds.new.add([])
            #print "\n"
          end
        # end
      end
      print "\n",reset

    end
  end

  class << self
    include Term::ANSIColor

    # for caching the the contents of YAML file $home/appliances
    # it is structured like :appliance_name => {:host => "htt[://api.gomorpheus.com", :active => true}
    # not named @@appliances to avoid confusion with the instance variable . This is also a command class...
    @@appliance_config = nil 

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
        Morpheus::Logging::DarkPrinter.puts "loading appliances file #{fn}" if Morpheus::Logging.debug?
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
      fn = appliances_file_path
      if !Dir.exists?(File.dirname(fn))
        FileUtils.mkdir_p(File.dirname(fn))
      end
      File.open(fn, 'w') {|f| f.write new_config.to_yaml } #Store
      FileUtils.chmod(0600, fn)
      #@@appliance_config = load_appliance_file
      @@appliance_config = new_config
    end

  end

end
