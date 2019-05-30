require 'fileutils'
require 'ostruct'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'net/https'
require 'optparse'
require 'morpheus/cli/cli_command'


class Morpheus::Cli::Remote
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :add, :get, :update, :remove, :use, :unuse, :current, :setup, :check
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
    show_all_activity = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on("-a",'--all', "Show all the appliance activity details") do
        show_all_activity = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields])
      opts.footer = <<-EOT
This outputs a list of the configured remote appliances. It also indicates
the current appliance. The current appliance is where morpheus will send 
its commands by default. That is, in absence of the '--remote' option.
EOT
    end
    optparse.parse!(args)
    if args.count > 0
      raise ::OptionParser::NeedlessArgument.new("#{args.join(' ')}")
    end
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    appliances = ::Morpheus::Cli::Remote.load_all_remotes({})
    # if appliances.empty?
    #   raise_command_error "You have no appliances configured. See the `remote add` command."
    # end
    
    json_response = {"appliances" => appliances}
    if options[:json]
      puts as_json(json_response, options, "appliances")
      return 0
    elsif options[:yaml]
      puts as_yaml(json_response, options, "appliances")
      return 0
    elsif options[:csv]
      puts records_as_csv(appliances, options)
      return 0
    end

    print_h1 "Morpheus Appliances", [], options
    if appliances.empty?
      print yellow
      puts "You have no appliances configured. See the `remote add` command."
      print reset, "\n"
    else
      print cyan
      columns = [
        {:active => {:display_name => "", :display_method => lambda {|it| it[:active] ? "=>" : "" } } },
        # {:name => {display_method: lambda {|it| it[:active] ? "#{green}#{it[:name]}#{reset}#{cyan}" : it[:name] }, :width => 16 } },
        {:name => {display_method: lambda {|it| it[:name] }, :width => 16 } },
        {:url => {display_method: lambda {|it| it[:host] || it[:url] }, :width => 40 } },
        {:version => lambda {|it| it[:build_version] } },
        {:status => lambda {|it| format_appliance_status(it, cyan) } },
        :username,
        # {:session => {display_method: lambda {|it| get_appliance_session_blurbs(it).join('  ') }, max_width: 24} }
        {:activity => {display_method: lambda {|it| show_all_activity ? get_appliance_session_blurbs(it).join("\t") : get_appliance_session_blurbs(it).first } } }
      ]
      print as_pretty_table(appliances, columns, options)
      print reset
      if @appliance_name
        #unless appliances.keys.size == 1
          print cyan, "\n# => #{@appliance_name} is the current remote appliance\n", reset
        #end
      else
        print "\n# => No current remote appliance, see `remote use`\n", reset
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    exit_code, err = 0, nil
    options = {}
    params = {}
    new_appliance_map = {}
    use_it = false
    is_insecure = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      banner = subcommand_usage("[name] [url]")
      banner_args = <<-EOT
    [name]                           The name for your appliance. eg. mymorph
    [url]                            The url of your appliance eg. https://morpheus.mycompany.com
EOT
      opts.banner = banner + "\n" + banner_args
      opts.on(nil, '--use', "Make this the current appliance" ) do
        use_it = true
        new_appliance_map[:active] = true
      end
      # let's free up the -d switch for global options, maybe?
      opts.on( '-d', '--default', "Does the same thing as --use" ) do
        use_it = true
        new_appliance_map[:active] = true
      end
      opts.on(nil, "--secure", "Prevent insecure HTTPS communication.  This is enabled by default.") do
        params[:secure] = true
      end
      opts.on(nil, "--insecure", "Allow insecure HTTPS communication.  i.e. Ignore SSL errors.") do
        params[:insecure] = true
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
This will add a new remote appliance to your morpheus client configuration.
If the new remote is your one and only, --use is automatically applied and 
it will be made the current remote appliance.
This command will prompt you to login and/or setup a fresh appliance.
Prompting can be skipped with use of the --quiet option.
EOT
    end
    optparse.parse!(args)
    if args.count < 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add expects 2 arguments: [name] [url]"
      puts_error optparse
      return 1
    end

    # load current appliances
    appliances = ::Morpheus::Cli::Remote.appliances

    # always use the first one
    if appliances.empty?
      new_appliance_map[:active] = true
    end

    # validate options
    # construct new appliance map
    # and save it in the config file
    new_appliance_name = args[0].to_sym

    # for the sake of sanity
    if [:current, :all].include?(new_appliance_name)
      raise_command_error "The specified appliance name is invalid: '#{args[0]}'"
    end
    # unique name
    if appliances[new_appliance_name] != nil
      raise_command_error "Remote appliance already configured with the name '#{args[0]}'"
    end
    new_appliance_map[:name] = new_appliance_name

    if params[:insecure]
      new_appliance_map[:insecure] = true
    elsif params[:secure]
      new_appliance_map.delete(:insecure)
    end
    if params[:url] || params[:host]
      url = params[:url] || params[:host]
    end

    url = args[1]
    if url !~ /^https?\:\/\/.+/
      raise_command_error "The specified appliance url is invalid: '#{args[1]}'"
      #puts optparse
      return 1
    end
    new_appliance_map[:host] = url

    # save it
    appliance = ::Morpheus::Cli::Remote.save_remote(new_appliance_name, new_appliance_map)

    if !options[:quiet]
      # print_green_success "Added remote #{new_appliance_name}"
      print_green_success "Added remote #{new_appliance_name}"
    end

    # hit check api and store version and other info
    if !options[:quiet]
      print cyan
      puts "Inspecting remote appliance url: #{appliance[:host]} ..."
    end
    appliance = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name)
    if !options[:quiet]
      print cyan
      puts "Status is: #{format_appliance_status(appliance)}"
    end
    # puts "refreshed appliance #{appliance.inspect}"
    # determine command exit_code and err
    exit_code = (appliance[:status] == 'ready' || appliance[:status] == 'fresh') ? 0 : 1

    if exit_code == 0
      if appliance[:error]
        exit_code = 1
        err = "Check Failed: #{appliance[:error]}"
      end
    end

    if options[:quiet]
      return exit_code, err
    end

    # check_cmd_result = check_appliance([new_appliance_name, "--quiet"])
    # check_cmd_result = check_appliance([new_appliance_name])

    if appliance[:status] == 'fresh' # || appliance[:setup_needed] == true
      print cyan
      puts "It looks like this appliance needs to be setup. Starting setup ..."
      return setup([new_appliance_name])
      # no need to login, setup() handles that
    end

    
    # only login if you are using this remote
    # maybe remote use should do the login prompting eh?
    # if appliance[:active] && appliance[:status] == 'ready'
    if appliance[:status] == 'ready'
      print reset
      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to login now?", options.merge({default: true}))
        login_result = ::Morpheus::Cli::Login.new.handle(["--remote", appliance[:name].to_s])
        keep_trying = true
        if login_result == 0
          keep_trying = false
        end
        while keep_trying do
          if ::Morpheus::Cli::OptionTypes::confirm("Login was unsuccessful. Would you like to try again?", options.merge({default: true}))
            login_result = ::Morpheus::Cli::Login.new.handle(["--remote", appliance[:name].to_s])
            if login_result == 0
              keep_trying = false
            end
          else
            keep_trying = false
          end
        end

      end

      if !appliance[:active]
        if ::Morpheus::Cli::OptionTypes::confirm("Would you like to switch to using this remote now?", options.merge({default: true}))
          use([appliance[:name]])
        end
      end

    else
      #puts "Status is #{format_appliance_status(appliance)}"
    end

    # print new appliance details
    _get(appliance[:name], {})

    return exit_code, err
  end

  def refresh(args)
    check_appliance(args)
  end

  def check(args)
    options = {}
    checkall = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = <<-EOT
#{subcommand_usage("[name]")}
    [name] is required. This is the name of the remote. Use 'current' to check the active appliance."
EOT
      #opts.banner = "#{opts.banner}\n" + "    " + "[name] is required. This is the name of the remote. Use 'current' to check the active appliance."
      opts.on("-a",'--all', "Refresh all appliances") do
        checkall = true
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
This can be used to refresh a remote appliance.
It makes an api request to the configured appliance url to check the status and version.
[name] is required. This is the name of the remote. Use 'current' to check the active appliance."
EOT
    end
    optparse.parse!(args)
    id_list = nil
    checkall = true if args[0] == "all" and args.size == 1 # sure, why not
    if checkall
      # id_list = ::Morpheus::Cli::Remote.appliances.keys # sort ?
      return _check_all_appliances()
    elsif args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} update expects argument [name] or option --all"
      puts_error optparse
      return 1
    else
      id_list = parse_id_list(args)
    end
    #connect(options)
    return run_command_for_each_arg(id_list) do |arg|
      _check_appliance(arg, options)
    end
  end

  def _check_all_appliances()
    # reresh all appliances and then display the list view
    id_list = ::Morpheus::Cli::Remote.appliances.keys # sort ?
    if id_list.size > 1
      print cyan
      print "Checking #{id_list.size} appliances "
    end
    id_list.each do |appliance_name|
      print "."
      ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    end
    print "\n"
    list([])

  end

  def _check_appliance(appliance_name, options)
    begin
      appliance = nil
      if appliance_name == "current"
        appliance = ::Morpheus::Cli::Remote.load_active_remote()
        if !appliance
          raise_command_error "No current appliance, see `remote use`."
        end
        appliance_name = appliance[:name]
      else
        appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
        if !appliance
          raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
        end
      end

      # found appliance
      # now refresh it
      
      start_time = Time.now
  
      Morpheus::Logging::DarkPrinter.puts "checking remote appliance url: #{appliance[:host]} ..." if Morpheus::Logging.debug?      

      appliance = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)

      took_sec = (Time.now - start_time)

      if options[:quiet]
        return 0
      end

      Morpheus::Logging::DarkPrinter.puts "remote appliance check completed in #{took_sec.round(3)}s" if Morpheus::Logging.debug?

      # puts "remote #{appliance[:name]} status: #{format_appliance_status(appliance)}"

      # if options[:json]
      #   print JSON.pretty_generate(json_response), "\n"
      #   return
      # end

      # show user latest info
      return _get(appliance[:name], {})

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    use_it = false
    is_insecure = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      # opts.on(nil, "--name STRING", "Update the name of your remote appliance") do |val|
      #   params['name'] = val
      # end
      opts.on("--url URL", String, "Update the url of your remote appliance") do |val|
        params[:host] = val
      end
      opts.on(nil, "--secure", "Prevent insecure HTTPS communication.  This is enabled by default") do
        params[:secure] = true
      end
      opts.on(nil, "--insecure", "Allow insecure HTTPS communication.  i.e. Ignore SSL errors.") do
        params[:insecure] = true
      end
      opts.on(nil, '--use', "Make this the current appliance" ) do
        use_it = true
        params[:active] = true
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = "This can be used to update remote appliance settings.\n"
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} update expects argument [name]."
      puts_error optparse
      return 1
    end

    appliance_name = args[0].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end

    # params[:url] = args[1] if args[1]
    
    if params.empty?
      print_error Morpheus::Terminal.angry_prompt
      puts_error "Specify at least one option to update"
      puts_error optparse
      return 1
    end
    
    if params[:insecure]
      appliance[:insecure] = true
    elsif params[:secure]
      appliance.delete(:insecure)
    end
    if params[:url] || params[:host]
      appliance[:host] = params[:url] || params[:host]
    end

    ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)

    print_green_success "Updated remote #{appliance_name}"
    # todo: just go ahead and refresh it now...
    # _check(appliance_name, {:quiet => true})
    appliance = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    # print new appliance details
    _get(appliance[:name], {})
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-u', '--url', "Print only the url." ) do
        options[:url_only] = true
      end
      build_common_options(opts, options, [:json,:csv, :fields, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get expects argument [name]."
      puts_error optparse
      return 1
    end
    #connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(appliance_name, options)
    begin
      appliance = nil
      if appliance_name == "current"
        appliance = ::Morpheus::Cli::Remote.load_active_remote()
        if !appliance
          raise_command_error "No current appliance, see `remote use`."
        end
        appliance_name = appliance[:name]
      else
        appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
        if !appliance
          raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
        end
      end

      if options[:json]
        json_response = {remote_appliance: appliance} # mock payload
        puts as_json(json_response, options)
        return
      end

      if options[:url_only]
        print cyan, appliance[:host],"\n",reset
        return 0
      end
      # expando
      # appliance = OStruct.new(appliance)

      # todo: just go ahead and refresh it now...
      # _check(appliance_name, {:quiet => true})
      # appliance = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)

      if appliance[:active]
        # print_h1 "Current Remote Appliance: #{appliance[:name]}"
        print_h1 "Morpheus Appliance", [], options
      else
        print_h1 "Morpheus Appliance", [], options
      end
      print cyan
      description_cols = {
        "Name" => :name,
        "URL" => :host,
        "Secure" => lambda {|it| format_appliance_secure(it) },
        "Version" => lambda {|it| it[:build_version] ? "#{it[:build_version]}" : 'unknown' },
        "Status" => lambda {|it| format_appliance_status(it, cyan) },
        "Username" => :username,
        # "Authenticated" => lambda {|it| format_boolean it[:authenticated] },
        # todo: fix this layout, obv
        "Activity" => lambda {|it| get_appliance_session_blurbs(it).join("\n" + (' '*10)) }
      }
      print cyan
      puts as_description_list(appliance, description_cols)

      # if appliance[:insecure]
      #   puts " Ignore SSL Errors: Yes"
      # else
      #   puts " Ignore SSL Errors: No"
      # end
      
      if appliance[:active]
        # print cyan
        print cyan, "# => #{appliance[:name]} is the current remote appliance.", reset, "\n\n"
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      # opts.on( '-f', '--force', "Remote appliance anyway??" ) do
      #   options[:default] = true
      # end
      opts.footer = "This will delete an appliance from your list."
      build_common_options(opts, options, [:auto_confirm, :quiet])
    end
    optparse.parse!(args)
    if args.count < 1
      #raise_command_error "#{command_name} remove requires argument [name].", optparse
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove requires argument [name]."
      puts_error optparse
      return 1, nil
    end
    appliance_name = args[0].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete '#{appliance_name}' from your list of remote appliances?", options)
      return 9, "aborted command" # new exit code for aborting confirmation
    end

    # ok, delete it
    ::Morpheus::Cli::Remote.delete_remote(appliance_name)

    # return result
    if options[:quiet]
      return 0, nil
    end
    print_green_success "Deleted remote #{appliance_name}"
    list([])
    return 0, nil
  end

  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet])
      opts.footer = "Make an appliance the current remote appliance.\n" +
                    "This allows you to switch between your different appliances.\n" + 
                    "You may override this with the --remote option in your commands."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} use expects argument [name]."
      puts_error optparse
      return 1
    end
    appliance_name = args[0].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end
    
    if appliance[:active] == true
      if !options[:quiet]
        print cyan
        puts "Using remote #{appliance_name} (still)"
      end
      return true
    end
    # appliance = ::Morpheus::Cli::Remote.set_active_appliance(appliance_name)
    appliance[:active] = true
    appliance = ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)
    
    # recalculate session variables
    ::Morpheus::Cli::Remote.recalculate_variable_map()

    if !options[:quiet]
      puts "#{cyan}Using remote #{appliance_name}#{reset}"
    end
    return true
  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "This clears the current remote appliance.\n" +
        "You will need to use an appliance, or pass the --remote option to your commands."
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    if !@appliance_name
      puts "You are not using any appliance"
      return false
    end
    Morpheus::Cli::Remote.clear_active_appliance()
    puts "You are no longer using the appliance #{@appliance_name}"
    # recalculate session variables
    ::Morpheus::Cli::Remote.recalculate_variable_map()
    return true
  end

  def current(args)
    options = {}
    name_only = false
    url_only = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on( '-n', '--name', "Print only the name." ) do
        name_only = true
      end
      opts.on( '-u', '--url', "Print only the url." ) do
        url_only = true
      end
      build_common_options(opts, options, [])
      opts.footer = "Print details about the current remote appliance." +
                    "The default behavior is the same as 'remote get current'."
    end
    optparse.parse!(args)

    if !@appliance_name
      print yellow, "No current appliance, see `remote use`\n", reset
      return 1
    end

    if name_only
      print cyan, @appliance_name,"\n",reset
      return 0
    elsif url_only
      print cyan, @appliance_url,"\n",reset
      return 0
    else
      return _get("current", options)
    end

    
  end

  # this is a wizard that walks through the /api/setup controller
  # it only needs to be used once to initialize a new appliance
  def setup(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.on('-I','--insecure', "Allow insecure HTTPS communication.  i.e. bad SSL certificate.") do |val|
        options[:insecure] = true
        Morpheus::RestClient.enable_ssl_verification = false
      end
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
      print_h1 "Morpheus Appliance Setup", [], options

      puts "It looks like you're the first one here."
      puts "Let's initialize your remote appliance at #{@appliance_url}"


      
      # Master Account
      print_h2 "Create Master Account", options
      account_option_types = [
        {'fieldName' => 'accountName', 'fieldLabel' => 'Master Account Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(account_option_types, options[:options])
      payload.merge!(v_prompt)

      # Master User
      print_h2 "Create Master User", options
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
      print_h2 "Initial Setup", options
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
        @setup_interface.setopts(options)
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

  def format_appliance_status(app_map, return_color=cyan)
    return "" if !app_map
    status_str = app_map[:status] || app_map['status'] || "unknown" # get_object_value(app_map, :status)
    status_str = status_str.empty? ? "unknown" : status_str.to_s.downcase
    out = ""
    if status_str == "new"
      out << "#{cyan}#{status_str.upcase}#{return_color}"
    elsif status_str == "ready"
      out << "#{green}#{status_str.upcase}#{return_color}"
    elsif status_str == "unreachable"
      out << "#{red}#{status_str.upcase}#{return_color}"
    elsif ['error', 'net-error', 'ssl-error', 'http-timeout', 'unreachable']
      out << "#{red}#{status_str.upcase.gsub('-',' ')}#{return_color}"
    elsif status_str == "fresh" 
      # cold appliance, needs setup
      out << "#{magenta}#{status_str.upcase}#{return_color}"
    else
      # dunno
      out << "#{status_str}"
    end
    out
  end

  def format_appliance_secure(app_map, return_color=cyan)
    return "" if !app_map
    out = ""
    app_url = (app_map[:host] || app_map[:url]).to_s
    is_ssl = app_url =~ /^https/
    if !is_ssl
      out << "No (no SSL)"
    else
      if app_map[:insecure]
        out << "No (Ignore SSL Errors)"
      else
        # should have a flag that gets set when everything actually looks good..
        out << "Yes"
      end
    end
    out
  end

  # get display info about the current and past sessions
  # 
  def get_appliance_session_blurbs(app_map)
    # app_map = OStruct.new(app_map)
    blurbs = []
    # Current User
    # 
    username = app_map[:username]
    
    if app_map[:status] == 'ready'

      if app_map[:authenticated]
        #blurbs << app_map[:username] ? "Authenticated as #{app_map[:username]}" : "Authenticated"
        blurbs << "Authenticated."
        if app_map[:last_login_at]
          blurbs << "Logged in #{format_duration(app_map[:last_login_at])} ago."
        end
      else
        if app_map[:last_logout_at]
          blurbs << "Logged out #{format_duration(app_map[:last_logout_at])} ago."
        else
          blurbs << "Logged out."
        end
        if app_map[:last_login_at]
          blurbs << "Last login at #{format_local_dt(app_map[:last_login_at])}."
        end
      end

      if app_map[:last_success_at]
        blurbs << "Last success at #{format_local_dt(app_map[:last_success_at])}"
      end

    else
      
      if app_map[:last_check]
        if app_map[:last_check][:timestamp]
          blurbs << "Last checked #{format_duration(app_map[:last_check][:timestamp])} ago."
        end
        if app_map[:last_check][:error]
          blurbs << "Error: #{app_map[:last_check][:error]}"
        end
        if app_map[:last_check][:http_status]
          blurbs << "HTTP #{app_map[:last_check][:http_status]}"
        end
      end

      if app_map[:last_success_at]
        blurbs << "Last Success: #{format_local_dt(app_map[:last_success_at])}"
      end

    end

    return blurbs
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
      app_url = app_map ? (app_map[:host] || app_map[:url]).to_s : nil
      if app_name
        return app_name, app_url
      else
        return nil, nil
      end
    end

    # Returns all the appliances in the configuration
    # @param params [Hash] not used right now
    # @return [Array] of appliances, all of them.
    def load_all_remotes(params={})
      if self.appliances.empty?
        return []
      end
      all_appliances = self.appliances.collect do |app_name, app_map|
        row = app_map.clone # OStruct.new(app_map) tempting
        row[:name] = app_name
        row
        # {
        #   active: v[:active],
        #   name: app_name,
        #   host: v[:host], # || v[:url],
        #   #"LICENSE": v[:licenseIsInstalled] ? "Installed" : "(unknown)" # never return a license key from the server, ever!
        #   status: v[:status],
        #   username: v[:username],
        #   last_check: v[:last_check],
        #   last_whoami: v[:last_whoami],
        #   last_api_request: v[:last_api_request],
        #   last_api_result: v[:last_api_result],
        #   last_command: v[:last_command],
        #   last_command_result: v[:last_command_result]
        # }
      end
      return all_appliances
    end

    # @return Hash info about the active appliance
    def load_active_remote()
      # todo: use this in favor of Remote.active_appliance perhaps?
      if self.appliances.empty?
        return nil
      end
      result = nil
      app_name, app_map = self.appliances.find {|k,v| v[:active] == true }
      if app_map
        result = app_map
        result[:name] = app_name # app_name.to_s to be more consistant with other display values
      end
      return result
    end

    # @param [String or Symbol] name of the remote to load (converted to symbol)
    # @return [Hash] info about the appliance
    def load_remote(app_name)
      if self.appliances.empty? || app_name.nil?
        return nil
      end
      result = nil
      app_map = self.appliances[app_name.to_sym]
      if app_map
        result = app_map
        result[:name] = app_name # .to_s probably better
      end
      return result
    end

    def set_active_appliance(app_name)
      app_name = app_name.to_sym
      new_appliances = self.appliances
      new_appliances.each do |k,v|
        is_match = (app_name ? (k == app_name) : false)
        if is_match
          v[:active] = true
        else
          v.delete(:active)
          # v.delete('active')
          # v[:active] = false
        end
      end
      save_appliances(new_appliances)
      return load_remote(app_name)
    end

    def clear_active_appliance
      #return set_active_appliance(nil)
      new_appliances = self.appliances
      new_appliances.each do |k,v|
        v.delete(:active)
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

    # save_remote updates the appliance info
    # @param app_name [Symbol] name and key for the appliance
    # @param app_map [Hash] appliance configuration data :url, :insecure, :active, :etc
    # @return [Hash] updated appliance config data
    def save_remote(app_name, app_map)
      app_name = app_name.to_sym
      # it's probably better to use load_appliance_file() here instead
      cur_appliances = self.appliances #.clone
      cur_appliances[app_name] = app_map
      cur_appliances[app_name] ||= {:status => "unknown", :error => "Bad configuration. Missing url. See 'remote update --url'" }
      
      # this is the new set_active_appliance(), instead just pass :active => true
      # remove active flag from others
      if app_map[:active]
        cur_appliances.each do |k,v|
          is_match = (app_name ? (k == app_name) : false)
          if is_match
            v[:active] = true
          else
            v.delete(:active)
            # v.delete('active')
            # v[:active] = false
          end
        end
      end

      # persist all appliances
      save_appliances(cur_appliances)
      # recalculate session variables
      recalculate_variable_map()
      return app_map
    end

    def delete_remote(app_name)
      app_name = app_name.to_sym
      cur_appliances = self.appliances #.clone
      app_map = cur_appliances[app_name]
      if !app_map
        return nil
      end
      # remove it from config and delete credentials
      cur_appliances.delete(app_name)
      ::Morpheus::Cli::Remote.save_appliances(cur_appliances)
      # this should be a class method too
      ::Morpheus::Cli::Credentials.new(app_name, nil).clear_saved_credentials(app_name)
      # delete from groups too..
      ::Morpheus::Cli::Groups.clear_active_group(app_name)
      # recalculate session variables
      recalculate_variable_map()
      # return the deleted value
      return app_map
    end

    # refresh_remote makes an api request to the configured appliance url
    # and updates the appliance's build version, status and last_check attributes
    def refresh_remote(app_name)
      # this might be better off staying in the CliCommands themselves
      # todo: public api /api/setup/check should move to /api/version or /api/server-info
      app_name = app_name.to_sym
      cur_appliances = self.appliances
      app_map = cur_appliances[app_name] || {}
      app_url = (app_map[:host] || app_map[:url]).to_s

      if !app_url
        raise "appliance config is missing url!" # should not need this
      end

      # todo: this insecure flag needs to applied everywhere now tho..
      if app_map[:insecure]
        Morpheus::RestClient.enable_ssl_verification = false
      end
      # Morpheus::RestClient.enable_http = app_map[:insecure].to_s == 'true'
      setup_interface = Morpheus::SetupInterface.new(app_url)
      begin
        now = Time.now.to_i
        app_map[:last_check] = {}
        app_map[:last_check][:success] = false
        app_map[:last_check][:timestamp] = Time.now.to_i
        # todo: move /api/setup/check to /api/version or /api/server-info
        check_json_response = setup_interface.check()
        # puts "REMOTE CHECK RESPONSE:"
        # puts JSON.pretty_generate(check_json_response), "\n"
        app_map[:last_check][:http_status] = 200
        app_map[:build_version] = check_json_response['buildVersion'] # || check_json_response['build_version']
        #app_map[:last_check][:success] = true
        if check_json_response['success'] == true
          app_map[:status] = 'ready'
          app_map[:last_check][:success] = true
          # consider bumping this after every successful api command
          app_map[:last_success_at] = Time.now.to_i
          app_map.delete(:error)
        end
        if check_json_response['setupNeeded'] == true
          app_map[:setup_needed] = true
          app_map[:status] = 'fresh'
        else
          app_map.delete(:setup_needed)
        end

      rescue SocketError => err
        app_map[:status] = 'unreachable'
        app_map[:last_check][:http_status] = nil
        app_map[:last_check][:error] = err.message
      rescue RestClient::Exceptions::Timeout => err
        # print_rest_exception(e, options)
        # exit 1
        app_map[:status] = 'http-timeout'
        app_map[:last_check][:http_status] = nil
      rescue Errno::ECONNREFUSED => err
        app_map[:status] = 'net-error'
        app_map[:last_check][:error] = err.message
      rescue OpenSSL::SSL::SSLError => err
        app_map[:status] = 'ssl-error'
        app_map[:last_check][:error] = err.message
      rescue RestClient::Exception => err
        app_map[:status] = 'http-error'
        app_map[:http_status] = err.response ? err.response.code : nil
        app_map[:last_check][:error] = err.message
        # fallback to /ping for older appliance versions (pre 2.10.5)
        begin
          Morpheus::Logging::DarkPrinter.puts "falling back to remote check via /ping ..." if Morpheus::Logging.debug?
          setup_interface.ping()
          app_map[:last_check][:ping_fallback] = true
          app_map[:last_check][:http_status] = 200
          app_map[:last_check][:success] = true
          app_map[:last_check][:ping_fallback] = true
          app_map[:build_version] = "" # unknown until whoami is executed..
          app_map[:status] = 'ready'
          # consider bumping this after every successful api command
          app_map[:last_success_at] = Time.now.to_i
          app_map.delete(:error)
        rescue => ping_err
          Morpheus::Logging::DarkPrinter.puts "/ping failed too: #{ping_err.message} ..." if Morpheus::Logging.debug?
        end
      rescue => err
        # should save before raising atleast..sheesh
        raise err
        # Morpheus::Cli::ErrorHandler.new.handle_error(e)
        app_map[:status] = 'error'
        app_map[:last_check][:error] = err.message
      end

      # if app_map[:status] == 'ready'
      #   app_map.delete(:error)
      # end

      # save changes to disk ... and
      # ... class variable returned by Remote.appliances is updated in there too...
      save_remote(app_name, app_map)

      # return the updated data
      return app_map

    end

    def recalculate_variable_map()
      Morpheus::Cli::Echo.recalculate_variable_map()
      # recalculate shell prompt after this change
      if Morpheus::Cli::Shell.has_instance?
        Morpheus::Cli::Shell.instance.reinitialize()
      end
    end

  end

end
