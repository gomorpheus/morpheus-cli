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

  register_subcommands :list, :add, :get, :update, :rename, :remove, :use, :unuse, :current
  register_subcommands :setup, :teardown, :check, :'check-all'

  set_default_subcommand :list

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts={})
    connect_opts = {:skip_verify_access_token => true}.merge(opts)
    @api_client = establish_remote_appliance_connection(connect_opts)
    @setup_interface = @api_client.setup
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    show_all_activity = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on("-a",'--all', "Show all the appliance activity details") do
        show_all_activity = true
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields])
      opts.footer = <<-EOT
This outputs a list of the configured remote appliances. It also indicates
the current appliance. The current appliance is where morpheus will send 
its commands by default. That is, in absence of the '--remote' option.
EOT
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    #connect(options)
    params.merge!(parse_list_options(options))
    appliances = ::Morpheus::Cli::Remote.load_all_remotes(params)
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
    if appliances.empty?
      if params[:phrase]
        print cyan,"0 remotes matched '#{params[:phrase]}'", reset, "\n"
      else
        print yellow,"You have no appliances configured. See the `remote add` command.", reset, "\n"
      end
    else
      title = "Morpheus Appliances"
      subtitles = parse_list_subtitles(options)
      print_h1 title, subtitles, options
      print cyan
      columns = [
        {:active => {:display_name => "", :display_method => lambda {|it| it[:active] ? "=>" : "" } } },
        # {:name => {display_method: lambda {|it| it[:active] ? "#{green}#{it[:name]}#{reset}#{cyan}" : it[:name] }, :width => 16 } },
        {:name => {display_method: lambda {|it| it[:name] } } },
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
        print cyan, "\n# => No current remote appliance, see `remote use`\n", reset
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
    secure = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      banner = subcommand_usage("[name] [url]")
      banner_args = <<-EOT
    [name]                           The name for your appliance. eg. mymorph
    [url]                            The url of your appliance eg. https://demo.mymorpheus.com
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
        secure = true
      end
      opts.on(nil, "--insecure", "Allow insecure HTTPS communication.  i.e. Ignore SSL errors.") do
        secure = false
      end
      build_common_options(opts, options, [:options, :quiet])
      opts.footer = <<-EOT
This will add a new remote appliance to your morpheus client configuration.
If this is your first remote, --use is automatically applied so
it will become the current remote appliance.
This command will prompt you to login and/or setup a fresh appliance.
To skip login/setup, use the --quiet option.
EOT
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end

    # load current appliances
    appliances = ::Morpheus::Cli::Remote.appliances

    # always use the first one
    if appliances.empty?
      new_appliance_map[:active] = true
    end

    new_appliance_name = args[0] if args[0]
    url = args[1] if args[1]

    # Name
    still_prompting = true
    while still_prompting do
      if new_appliance_name.to_s.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'A unique name for the remote Morpheus appliance. Example: local'}], options[:options])
        new_appliance_name = v_prompt['name']
      end

      # for the sake of sanity
      if [:current, :all].include?(new_appliance_name.to_sym)
        raise_command_error "The specified appliance name '#{new_appliance_name}' is invalid."
        new_appliance_name = nil
      end
      # unique name
      existing_appliance = appliances[new_appliance_name.to_sym]
      if existing_appliance
        print_error red,"The specified appliance name '#{new_appliance_name}' already exists with the URL #{existing_appliance[:url] || existing_appliance[:host]}",reset,"\n"
        new_appliance_name = nil
      end

      if new_appliance_name.to_s.empty?
        if options[:no_prompt]
          return 1
        end
        still_prompting = true
      else
        still_prompting = false
      end
    end

    new_appliance_map[:name] = new_appliance_name.to_sym

    # URL
    still_prompting = true
    while still_prompting do
      if !url
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'url', 'fieldLabel' => 'URL', 'type' => 'text', 'required' => true, 'description' => 'The URL of the remote Morpheus appliance. Example: https://10.0.2.2'}], options[:options])
        url = v_prompt['url']
      end

      if url !~ /^https?\:\/\/.+/
        print_error red,"The specified appliance url '#{url}' is invalid.",reset,"\n"
        still_prompting = true
        url = nil
      else
        still_prompting = false
      end
    end

    # let's replace :host with :url
    new_appliance_map[:host] = url
    new_appliance_map[:url] = url

    # Insecure?
    if url.include?('https:') && secure.nil?
      # This is kind of annoying to always see, just default to true, use --insecure if you need to.
      #v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'secure', 'fieldLabel' => 'Secure', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true, 'description' => 'Prevent insecure HTTPS communication.  This is enabled by default.'}], options[:options])
      #secure = v_prompt['secure'].to_s == 'true' || v_prompt['secure'].to_s == 'on'
    end

    if secure == false
      new_appliance_map[:insecure] = true
    end

    # save it
    appliance = ::Morpheus::Cli::Remote.save_remote(new_appliance_name.to_sym, new_appliance_map)

    if !options[:quiet]
      # print_green_success "Added remote #{new_appliance_name}"
      print_green_success "Added remote #{new_appliance_name}"
    end

    # hit check api and store version and other info
    if !options[:quiet]
      print cyan
      puts "Inspecting remote appliance #{appliance[:host]} ..."
    end
    appliance, check_json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name.to_sym)
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

    if options[:json]
      puts as_json(check_json_response, options)
      return exit_code, err
    end

    # just skip setup/login stuff is no prompt -N is used.
    if options[:no_prompt]
      return exit_code, err
    end

    # check_cmd_result = check_appliance([new_appliance_name, "--quiet"])
    # check_cmd_result = check_appliance([new_appliance_name])

    if appliance[:status] == 'fresh' # || appliance[:setup_needed] == true

      if !appliance[:active]
        if ::Morpheus::Cli::OptionTypes::confirm("Would you like to switch to using this remote now?", options.merge({default: true}))
          use([appliance[:name]])
          appliance[:active] = true # just in case, could reload instead with load_active_remote()
        end
      end

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
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :quiet, :dry_run, :remote])
      opts.footer = <<-EOT
Check the status of a remote appliance.
[name] is optional. This is the name of a remote.  Default is the current remote. Can be passed as 'all'. to perform remote check-all.
This makes a request to the configured appliance url and updates the status and version.
EOT
    end
    optparse.parse!(args)
    
    if args.count == 0
      id_list = ['current']
    else
      id_list = parse_id_list(args)
    end
    # trick for remote check all
    if id_list.length == 1 && id_list[0].to_s.downcase == 'all'
      return _check_all_appliances(options)
    end
    #connect(options)
    return run_command_for_each_arg(id_list) do |arg|
      _check_appliance(arg, options)
    end
  end

  def _check_appliance(appliance_name, options)
    exit_code, err = 0, nil
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
          raise_command_error "Remote not found by the name '#{appliance_name}'"
        end
      end

      # found appliance, now refresh it
      
      start_time = Time.now
  
      # print cyan
      # print "Checking remote url: #{appliance[:host]} ..."

      appliance, check_json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)

      took_sec = (Time.now - start_time)

      exit_code = (appliance[:status] == 'ready' || appliance[:status] == 'fresh') ? 0 : 1

      if exit_code == 0
        if appliance[:error]
          exit_code = 1
          err = "Check Failed: #{appliance[:error]}"
        end
      end

      render_result = render_with_format(check_json_response, options)
      return exit_code if render_result

      print_green_success "Completed remote check of #{appliance_name} in #{took_sec.round(3)}s"

      return _get(appliance[:name], {})

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def check_all(args)
    options = {}
    checkall = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Refresh all remote appliances.
This makes a request to each of the configured appliance urls and updates the status and version.
EOT
    end
    optparse.parse!(args)

    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect() # needed?
    _check_all_appliances(options)
  end
  
  def _check_all_appliances(options)
    start_time = Time.now
    # reresh all appliances and then display the list view
    id_list = ::Morpheus::Cli::Remote.appliances.keys # sort ?
    if id_list.size > 1
      print cyan
      puts "Checking #{id_list.size} appliances"
    elsif id_list.size == 1
      puts "Checking #{Morpheus::Cli::Remote.appliances.keys.first}"
    end
    id_list.each do |appliance_name|
      #print "."
      appliance, check_json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    end
    took_sec = (Time.now - start_time)
    print_green_success "Completed remote check of #{id_list.size} #{id_list.size == 1 ? 'appliance' : 'appliances'} in #{took_sec.round(3)}s"
    
    if options[:quiet]
      return 0
    end
    list([])
    return 0
  end

  def rename(args)
    options = {}
    params = {}
    use_it = false
    is_insecure = nil
    new_name = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [new name]")
      opts.on(nil, "--name NAME", "Update the name of your remote appliance") do |val|
        new_name = val
      end
      
      # opts.on(nil, '--use', "Make this the current appliance" ) do
      #   use_it = true
      #   params[:active] = true
      # end
      build_common_options(opts, options, [:auto_confirm, :quiet])
            opts.footer = <<-EOT
Rename a remote.
This changes your client configuration remote name, not the appliance itself.
[name] is required. This is the current name of a remote.
[new name] is required. This is the new name for the remote. This must not already be in use.
EOT
    end
    optparse.parse!(args)
    if args.count != 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} rename expects argument [name]."
      puts_error optparse
      return 1
    end
    appliance_name = args[0].to_sym
    new_appliance_name = args[1].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end
    # don't allow overwrite yet
    matching_appliance = ::Morpheus::Cli::Remote.load_remote(new_appliance_name)
    if matching_appliance
      raise_command_error "Remote appliance already exists with the name '#{new_appliance_name}'"
    end
    
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to rename #{appliance_name} to  #{new_appliance_name}?", options)
      return 9, "aborted command"
    end
    # this does all the work
    ::Morpheus::Cli::Remote.rename_remote(appliance_name, new_appliance_name)

    print_green_success "Renamed remote #{appliance_name} to #{new_appliance_name}"
    # todo: just go ahead and refresh it now...
    # _check(appliance_name, {:quiet => true})
    # appliance, check_json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name)
    # print new appliance details
    _get(new_appliance_name, {})
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    use_it = false
    is_insecure = nil
    new_name = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on(nil, "--name NAME", "Update the name of your remote appliance") do |val|
        new_name = val
      end
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
    appliance, check_json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
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
    exit_code, err = 0, nil
    begin
      appliance = nil
      if appliance_name == "current"
        appliance = ::Morpheus::Cli::Remote.load_active_remote()
        if !appliance
          err = "No current appliance, see `remote use`."
          exit_code = 1
        end
        appliance_name = appliance[:name]
      else
        appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
        if !appliance
          err = "Remote appliance not found by the name '#{appliance_name}'"
          exit_code = 1
        end
      end

      if options[:quiet]
        return exit_code, err
      end

      if options[:json]
        json_response = {'appliance' => appliance} # mock payload
        puts as_json(json_response, options, "appliance")
        return exit_code, err
      end

      if options[:yaml]
        json_response = {'appliance' => appliance} # mock payload
        puts as_yaml(json_response, options, "appliance")
        return exit_code, err
      end

      

      if options[:url_only]
        if appliance
          print cyan, (appliance[:url] || appliance[:host]),"\n",reset
          return exit_code, err
        else
          print_error red, err,"\n",reset
          return exit_code, err
        end
      end
      
      if exit_code != 0
        print_error red, err,"\n",reset
        return exit_code, err
      end

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
      build_common_options(opts, options, [:auto_confirm, :quiet])
      opts.footer = <<-EOT
This will delete the specified remote appliance(s) from your local configuration.
[name] is required. This is the name of a remote. More than one can be passed.
EOT
    end
    optparse.parse!(args)
    if args.count == 0
      #id_list = ['current']
      raise_command_error "wrong number of arguments, expected 1-N and got 0\n#{optparse}"
    else
      id_list = parse_id_list(args)
    end
    #connect(options)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete #{id_list.size == 1 ? 'remote' : 'remotes'}: #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _remove_appliance(arg, options)
    end
  end

  def _remove_appliance(appliance_name, options)
    
    appliance_name = appliance_name.to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end
    

    appliances = ::Morpheus::Cli::Remote.appliances

    if appliances[appliance_name].nil?
      if options[:quiet]
        return 1
      end
      print_red_alert "Remote does not exist with name '#{appliance_name.to_s}'"
      return 1
    end

    # ok, delete it

    ::Morpheus::Cli::Remote.delete_remote(appliance_name)

    # return result
    if options[:quiet]
      return 0
    end
    print_green_success "Deleted remote #{appliance_name}"
    # list([])
    return 0
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
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} use expects argument [name]."
      puts_error optparse
      return 1
    end
    current_appliance_name, current_appliance_url = @appliance_name, @appliance_url 
    appliance_name = args[0].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}'"
    end
    
    # appliance = ::Morpheus::Cli::Remote.set_active_appliance(appliance_name)
    appliance[:active] = true
    appliance = ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)

    if options[:quiet]
      return 0
    end

    if current_appliance_name.to_s == appliance_name.to_s
      print green, "Using remote #{appliance_name} (still)", reset, "\n"
    else
      print green, "Using remote #{appliance_name}", reset, "\n"
    end
    
    # recalculate session variables
    ::Morpheus::Cli::Remote.recalculate_variable_map()

    return 0
  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "This clears the current remote appliance.\n"
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    #connect(options)
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    if !@appliance_name
      print yellow,"You are not using any appliance",reset,"\n"
      return 0
    end
    Morpheus::Cli::Remote.clear_active_appliance()
    print cyan, "You are no longer using the appliance #{@appliance_name}", reset, "\n"
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
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    # if !@appliance_name
    #   print yellow, "No current appliance, see `remote use`\n", reset
    #   return 1
    # end
    #connect(options)
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
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.on('--hubmode MODE','--hubmode MODE', "Choose an option for hub registration possible values are login, register, skip.") do |val|
        options[:hubmode] = val.to_s.downcase
      end
      opts.footer = "Initialize a fresh appliance.\n" + 
                    "You will be prompted to create the master tenant and admin user.\n" + 
                    "If Morpheus Hub registration is enabled, you may login or register to retrieve a license key.\n" + 
                    "Setup is only available on a new, freshly installed, remote appliance\n" + 
                    "and it may only be used successfully once."
    end
    optparse.parse!(args)
    
    # first arg as remote name otherwise the active appliance is connected to
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      options[:remote] = args[0]
    end
    connect(options)

    if !@appliance_name
      print yellow, "No active appliance, see `remote use`\n", reset
      return false
    end

    # construct payload
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      params = {}
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # this works without any authentication!
      # it will allow anyone to use it, if there are no users/accounts in the system.
      #@api_client = establish_remote_appliance_connection(options)
      @setup_interface = @api_client.setup #use me
      # @setup_interface = Morpheus::SetupInterface.new({url:@appliance_url,access_token:@access_token})
      appliance_status_json = nil
      begin
        appliance_status_json = @setup_interface.get()
        if appliance_status_json['success'] != true
          print_error red, "Setup not available for appliance #{@appliance_name} - #{@appliance_url}.\n", reset
          print_error red, "#{appliance_status_json['msg']}\n", reset
          return false
        end
      rescue RestClient::Exception => e
        print_rest_exception(e, options)
        return false
      end

      # retrieved hub.enabled and hub.url 
      hub_settings = appliance_status_json['hubSettings'] || appliance_status_json['hub'] || {}

      # store login/registration info in here, for prompt default values
      hub_info = nil
      print cyan
      print_h2 "Remote Setup: #{@appliance_name} - #{@appliance_url}"
      
      print cyan
      puts "Welcome to the setup of your new Morpheus Appliance #{@appliance_name} @ #{@appliance_url}"
      puts "It looks like you're the first here, so let's begin."

      hubmode = nil
      hub_init_payload = nil # gets included as payload for hub scoped like hub.email
      if hub_settings['enabled']

        # Hub Registration
          hub_action_dropdown = [
            {'name' => 'Login to existing hub account', 'value' => 'login', 'isDefault' => true}, 
            {'name' => 'Register a new hub account', 'value' => 'register'}, 
            {'name' => 'Skip this step and manually install a license later.', 'value' => 'skip'},
            {'name' => 'Abort', 'value' => 'abort'}
          ]
          

        print cyan
        puts "Morpheus Hub registration is enabled for your appliance."
        puts "This step will connect to the Morpheus Hub at #{hub_settings['url']}"
        puts "This is done to retrieve and install the license key for your appliance."
        puts "You have several options for how to proceed:"
        hub_action_dropdown.each_with_index do |hub_action, idx|
          puts "#{idx+1}. #{hub_action['name']} [#{hub_action['value']}]"
        end
        print "\n", reset

        while hubmode == nil do
          
          options[:options]['hubmode'] = options[:hubmode] if options.key?(:hubmode)
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hubmode', 'fieldLabel' => 'Choose Hub Mode', 'type' => 'select', 'selectOptions' => hub_action_dropdown, 'required' => true, 'defaultValue' => 'login'}], options[:options])
          hubmode = v_prompt['hubmode']

          if hubmode == 'login'

            # print cyan
            # puts "MORPHEUS HUB #{hub_settings['url']}"
            # puts "The Command Center for DevOps"
            # print reset

            # Hub Login
            print_h2 "Morpheus Hub Login @ #{hub_settings['url']}", options
            hub_login_option_types = [
              {'fieldContext' => 'hub', 'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'description' => 'Email Address of existing Morpheus Hub user to link with.'},
              {'fieldContext' => 'hub', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'description' => 'Password of existing Morpheus Hub user.'},
            ]
            v_prompt = Morpheus::Cli::OptionTypes.prompt(hub_login_option_types, options[:options])
            hub_login_payload = v_prompt['hub']
            hub_login_response = nil
            begin
              hub_login_response = @setup_interface.hub_login(hub_login_payload)
              hub_init_payload = hub_login_payload
              hub_info = {'email' => hub_login_payload['email'], 'password' => hub_login_payload['password'] }
              hub_info.deep_merge!(hub_login_response['data']['info']) if (hub_login_response['data'] && hub_login_response['data']['info'])
              hub_info.deep_merge!(hub_login_response['hub']) if hub_login_response['hub'].is_a?(Hash)
              print_green_success "Logged into Morpheus Hub as #{hub_info['email']}"
            rescue RestClient::Exception => e
              hub_login_response = parse_rest_exception(e)
              error_msg = hub_login_response["msg"] || "Hub login failed."
              print_error red,error_msg,reset,"\n"
              hubmode = nil
              #print_rest_exception(e, options)
              #exit 1
            end
            
            # DEBUG
            if options[:debug] && hub_login_response
              print_h2 "JSON response for hub login"
              Morpheus::Logging::DarkPrinter.puts as_json(hub_login_response)
            end

          elsif hubmode == 'register'
            # Hub Registration
            print_h2 "Morpheus Hub Registration", options
            hub_register_option_types = [
              {'fieldContext' => 'hub', 'fieldName' => 'companyName', 'fieldLabel' => 'Company Name', 'type' => 'text', 'required' => true, 'description' => 'Company Name of new Morpheus Hub account to be created.'},
              {'fieldContext' => 'hub', 'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => true, 'description' => 'First Name of new Morpheus Hub user.'},
              {'fieldContext' => 'hub', 'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => true, 'description' => 'Last Name of new Morpheus Hub user.'},
              {'fieldContext' => 'hub', 'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'description' => 'Email Address of new Morpheus Hub user.'}
            ]
            v_prompt = Morpheus::Cli::OptionTypes.prompt(hub_register_option_types, options[:options])
            hub_register_payload = v_prompt['hub']

            # Password prompt with re-prompting if no match
            need_password = true
            if options[:no_prompt]
              if options[:options]['hub'] && options[:options]['hub']['password']
                options[:options]['hub']['confirmPassword'] = options[:options]['hub']['password']
              end
            end
            while need_password do
              password_option_types = [
                {'fieldContext' => 'hub', 'fieldName' => 'password', 'fieldLabel' => 'Create Password', 'type' => 'password', 'required' => true, 'description' => 'Confirm password of new Morpheus Hub user.'},
                {'fieldContext' => 'hub', 'fieldName' => 'confirmPassword', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'description' => 'Confirm password of new Morpheus Hub user.'}
              ]
              v_prompt = Morpheus::Cli::OptionTypes.prompt(password_option_types, options[:options])
              if v_prompt['hub']['password'] == v_prompt['hub']['confirmPassword']
                hub_register_payload.deep_merge!(v_prompt['hub'])
                need_password = false
              else
                print_error red, "Password confirmation does not match. Re-enter your new password.", reset, "\n"
              end
            end

            begin
              hub_register_response = @setup_interface.hub_register(hub_register_payload)
              hub_init_payload = hub_register_payload
              hub_info = {'email' => hub_register_payload['email'], 'password' => hub_register_payload['password'] }
              hub_info.deep_merge!(hub_register_payload)
              hub_info.deep_merge!(hub_register_response['data']['info']) if (hub_register_response['data'] && hub_register_response['data']['info'])
              hub_info.deep_merge!(hub_register_response['hub']) if hub_register_response['hub'].is_a?(Hash)
              print_green_success "Registered with Morpheus Hub as #{hub_info['email']}"
              # uh ok so that means the init() request can use login
              # this avoid duplicate email error
              # but it can also just omit hubMode from the init() payload to achieve the same thing.
              # hubmode = nil
            rescue RestClient::Exception => e
              hub_register_response = parse_rest_exception(e)
              error_msg = hub_register_response["msg"] || "Hub Registration failed."
              print_error red,error_msg,reset,"\n"
              hubmode = nil
              #print_rest_exception(e, options)
              #exit 1
            end
            
            # DEBUG
            if options[:debug] && hub_register_response
              print_h2 "JSON response for hub registration"
              Morpheus::Logging::DarkPrinter.puts as_json(hub_register_response)
            end
            
          elsif hubmode == 'skip'
            print cyan,"Skipping hub registraton for now...",reset,"\n"
            # puts "You may enter a license key later."
          elsif hubmode == 'abort'
            return 9, "aborted command"
          else
            hubmode = nil
          end
        end
      end

      # ok, we're done with the hub.
      # now build the payload for POST /api/setup/init

      payload = {}
      payload.deep_merge!(params)

      # print cyan
      #print_h1 "Morpheus Appliance Setup", [], options
      #print cyan
      #puts "Initializing remote appliance at URL: #{@appliance_url}"

      # Master Account
      print_h2 "Create Master Tenant", options
      account_option_types = [
        {'fieldName' => 'accountName', 'fieldLabel' => 'Master Tenant Name', 'type' => 'text', 'required' => true, 'defaultValue' => (hub_info ? hub_info['companyName'] : nil), 'description' => 'A unique name for the Master Tenant (account).'},
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(account_option_types, options[:options])
      payload.merge!(v_prompt)

      # Master User
      print_h2 "Create Master User", options
      user_option_types = [
        {'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'defaultValue' => (hub_info ? hub_info['firstName'] : nil), 'description' => 'First name of the user.'},
        {'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'defaultValue' => (hub_info ? hub_info['lastName'] : nil), 'description' => 'Last name of the user.'},
        {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'defaultValue' => (hub_info ? hub_info['email'] : nil), 'description' => 'A unique email address for the user.'},
        {'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'description' => 'A unique username for the master user.'}
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(user_option_types, options[:options])
      payload.merge!(v_prompt)

      # Password prompt with re-prompting if no match
      need_password = true
      if options[:no_prompt]
        options[:options]['confirmPassword'] = payload['password']
        payload['confirmPassword'] = payload['password'] if payload['password']
      end
      while need_password do
        password_option_types = [
          {'fieldName' => 'password', 'fieldLabel' => 'Create Password', 'type' => 'password', 'required' => true, 'description' => 'Create a new password for the user.'},
          {'fieldName' => 'confirmPassword', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'description' => 'Confirm the new password for the user.'},
        ]
        password_prompt = Morpheus::Cli::OptionTypes.prompt(password_option_types, options[:options])
        if password_prompt['password'] == password_prompt['confirmPassword']
          payload['password'] = password_prompt['password']
          need_password = false
        else
          print_error red, "Password confirmation does not match. Re-enter your new password.", reset, "\n"
        end
      end

      # Appliance Settings
      default_appliance_url = appliance_status_json['applianceUrl']
      if default_appliance_url && default_appliance_url.include?('10.0.2.2:8080') # ignore this default value.
        default_appliance_url = @appliance_url
      end
      default_appliance_name = appliance_status_json['applianceName']
      if default_appliance_name.nil?
        default_appliance_name = @appliance_name
      end
      print_h2 "Initial Setup", options
      extra_option_types = [
        {'fieldName' => 'applianceName', 'fieldLabel' => 'Appliance Name', 'type' => 'text', 'required' => true, 'defaultValue' => default_appliance_name, 'description' => 'A name for identifying your morpheus appliance.'},
        {'fieldName' => 'applianceUrl', 'fieldLabel' => 'Appliance URL', 'type' => 'text', 'required' => true, 'defaultValue' => default_appliance_url, 'description' => 'Appliance URL. Can be used for integrations and callbacks.'},
        {'fieldName' => 'backups', 'fieldLabel' => 'Enable Backups', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'off', 'description' => 'Backups. Default is off. This means backups are created automatically during provisioning.'},
        {'fieldName' => 'monitoring', 'fieldLabel' => 'Enable Monitoring', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'on', 'description' => 'Enable Monitoring. This means checks are created automatically during provisioning.'},
        {'fieldName' => 'logs', 'fieldLabel' => 'Enable Logs', 'type' => 'checkbox', 'required' => false, 'defaultValue' => 'on', 'description' => 'Enable Logs. This means container logs are collected.'}
      ]
      v_prompt = Morpheus::Cli::OptionTypes.prompt(extra_option_types, options[:options])
      payload.merge!(v_prompt)
      
      # include hubmode and hub params for login or registration
      # actually we remove hubMode because it has already been setup, probably just now,
      # and the init() request will just used the same creds instead of 
      # reauthenticated/registering with the hub
      if hubmode
        payload['hubMode'] = hubmode
      end
      if hub_init_payload
        payload['hub'] = hub_init_payload
      end
      if hubmode == 'register' || hubmode == 'login'
        payload.delete('hubMode')
        payload.delete('hub')
      end

    end
      
    # ok, make the api request
    @setup_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @setup_interface.dry.init(payload)
      return
    end

    json_response = @setup_interface.init(payload)

    render_result = render_with_format(json_response, options)
    return 0 if render_result

    if options[:json]
      print JSON.pretty_generate(json_response)
      print "\n"
      return
    end
    print "\n"
    print green,"Setup complete for remote #{@appliance_name} - #{@appliance_url}",reset,"\n"
    #print cyan, "You may now login with the command `login`.\n"
    # uh, just use Credentials.login(username, password, {save: true})
    cmd_res = Morpheus::Cli::Login.new.login(['--username', payload['username'], '--password', payload['password'], '-q'] + (options[:remote] ? ["-r",options[:remote]] : []))
    # print "\n"
    print cyan, "You are now logged in as the System Admin #{payload['username']}.\n"
    print reset
    #print "\n"

    if hubmode == 'skip'
      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to apply your License Key now?", options.merge({:default => true}))
        cmd_res = Morpheus::Cli::License.new.apply([] + (options[:remote] ? ["-r",options[:remote]] : []))
        # license_is_valid = cmd_res != false
      end
    end

    if ::Morpheus::Cli::OptionTypes::confirm("Do you want to create the first group now?", options.merge({:default => true}))
      cmd_res = Morpheus::Cli::Groups.new.add(['--use'] + (options[:remote] ? ["-r",options[:remote]] : []))

      #print "\n"

      # if cmd_res !=
        if ::Morpheus::Cli::OptionTypes::confirm("Do you want to create the first cloud now?", options.merge({:default => true}))
          cmd_res = Morpheus::Cli::Clouds.new.add([] + (options[:remote] ? ["-r",options[:remote]] : []))
          #print "\n"
        end
      # end
    end
    print "\n",reset

  end


  # this is just for testing new appliances really
  # it can be used
  def teardown(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = "Provides a way to uninitialize a fresh appliance. Useful for testing appliance setup."
    end
    optparse.parse!(args)
    
    # first arg as remote name otherwise the active appliance is connected to
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    if args[0]
      options[:remote] = args[0]
    end
    connect(options)

    if !@appliance_name
      print yellow, "No active appliance, see `remote use`\n", reset
      return false
    end

    unless options[:quiet]
      print yellow
      print "\n"
      puts "WARNING: You are about to reset your appliance installation."
      puts "It's only possible to perform teardown when the appliance has just been installed."
      puts "This provides a way to reset your appliance and run setup again."
      print reset
      print "\n"
    end

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like teardown appliance '#{@appliance_name}'.", options)
      return 9, "aborted command" # new exit code for aborting confirmation
    end

    #@setup_interface = @api_client.setup

    # construct payload

    params = {}
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # this works without any authentication!
    # it will allow anyone to use it, if there are no users/accounts in the system.
    #@api_client = establish_remote_appliance_connection(options)
    #@setup_interface = @api_client.setup
    @setup_interface = Morpheus::SetupInterface.new({url:@appliance_url,access_token:@access_token, very_ssl:false})
    json_response = nil
    begin
      json_response = @setup_interface.teardown(params)
      if json_response['success'] != true
        print_error red, (json_response['msg'] || "Teardown failed").to_s, reset, "\n"
        return false
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return false
    end


    # ok, make the api request and render the response or print a message
    @setup_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @setup_interface.dry.teardown(params)
      return
    end

    json_response = @setup_interface.teardown(params)

    render_result = render_with_format(json_response, options)
    return 0 if render_result
    if options[:quiet]
      return 0
    end
    if json_response['msg']
      print_green_success json_response['msg']
    else
      print_green_success "Teardown complete for remote #{@appliance_name} - #{@appliance_url}. Now see `remote setup`"
    end
    return 0

  end

  def format_appliance_status(app_map, return_color=cyan)
    return "" if !app_map
    status_str = app_map[:status] || app_map['status'] || "unknown" # get_object_value(app_map, :status)
    status_str = status_str.empty? ? "unknown" : status_str.to_s.downcase
    out = ""
    if status_str == "new"
      out << "#{cyan}#{status_str.upcase}#{return_color}"
    elsif status_str == "fresh"
      # maybe just green instead?
      out << "#{magenta}#{status_str.upcase}#{return_color}"
    elsif status_str == "ready"
      out << "#{green}#{status_str.upcase}#{return_color}"
    elsif status_str == "http-error"
      out << "#{red}HTTP ERROR#{return_color}"
    elsif ['error', 'net-error', 'ssl-error', 'http-timeout', 'unreachable', 'unrecognized'].include?(status_str)
      out << "#{red}#{status_str.gsub('-', ' ').upcase}#{return_color}"
    else
      # dunno
      out << "#{yellow}#{status_str.upcase}#{return_color}"
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
          last_error_msg = truncate_string(app_map[:last_check][:error], 250)
          blurbs << "Error: #{last_error_msg}"
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
      
      # filter results
      params[:phrase] = params['phrase'] if params['phrase']
      params[:name] = params['name'] if params['name']
      params[:url] = params['url'] if params['url']
      # params[:insecure] = params['insecure'] if params['insecure']
      params[:max]  = params['max'] if params['max']
      params[:offset] = params['offset'] if params['offset']
      params[:sort] = params['sort'] if params['sort']
      params[:direction] = params['direction'] if params['direction']
      

      if all_appliances
        # apply filters
        if params[:phrase]
          all_appliances = all_appliances.select do |app|
            app_name = app[:name] || app['name']
            app_url = app[:url] || app['url'] || app[:host]
            app_name.to_s.include?(params[:phrase]) || app_url.to_s.include?(params[:phrase])
          end
        end
        # apply sort
        sort_key = params[:sort] ? params[:sort].to_sym : :name
        if params['direction'] == 'desc'
          all_appliances = all_appliances.sort {|a,b| b[sort_key] <=> a[sort_key] }
        else
          all_appliances = all_appliances.sort {|a,b| a[sort_key] <=> b[sort_key] }
        end
        # limit
        if params[:max]
          all_appliances = all_appliances.first(params[:max])
        end
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
        #Morpheus::Logging::DarkPrinter.puts "loading appliances file #{fn}" if Morpheus::Logging.debug?
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

    # use this to rename, it update appliances file and others.
    # oh maybe just put this in the command handler
    #
    # first check if the requested name exits
    # and that the new name does not exist.
    #
    # clone it and delete the old one.
    # todo: switch replace symbols with strings please, makes for nicer appliances.yaml 
    def rename_remote(app_name, new_app_name)
      app_name = app_name.to_sym
      new_app_name = new_app_name.to_sym
      cur_appliances = self.appliances #.clone
      app_map = cur_appliances[app_name]
      if app_map.nil?
        print_red_alert "A remote not found by the name '#{app_name}'"
        #print "Did you mean one of these commands: #{suggestions.join(', ')?", reset, "\n"
        return nil
      end
      if cur_appliances[new_app_name]
        print_red_alert "A remote already exists with name '#{new_app_name}'."
        puts "First, you must rename or remove the existing remote."
        return nil
      end
      
      # clone the existing data

      # copy remote
      new_appliance_map = app_map.clone()
      new_appliance_map[:name] = new_app_name # inject name
      save_remote(new_app_name, new_appliance_map)

      # clone credentials...just overwrite keys there, f it.
      old_wallet = ::Morpheus::Cli::Credentials.new(app_name, nil).load_saved_credentials()
      if old_wallet
        ::Morpheus::Cli::Credentials.new(new_app_name, nil).save_credentials(new_app_name, old_wallet)
        #::Morpheus::Cli::Credentials.new(app_name, nil).clear_saved_credentials(app_name)
      end
      # clone groups...just overwrite keys there, f it.
      old_active_group = ::Morpheus::Cli::Groups.active_group(app_name)
      if old_active_group
        ::Morpheus::Cli::Groups.set_active_group(new_app_name, old_active_group)
        #::Morpheus::Cli::Groups.clear_active_group(app_name)
      end
       
      # delete stuff last
      
      # delete creds
      if old_wallet
        ::Morpheus::Cli::Credentials.new(app_name, nil).clear_saved_credentials(app_name)
      end
      
      # delete groups
      if old_active_group
        ::Morpheus::Cli::Groups.clear_active_group(app_name)
      end

      # delete remote
      delete_remote(app_name)

      # this is all redundant after above
      # # this should be a class method too
      # ::Morpheus::Cli::Credentials.new(app_name, nil).clear_saved_credentials(app_name)
      # # delete from groups too..
      # ::Morpheus::Cli::Groups.clear_active_group(app_name)
      # # recalculate session variables
      # recalculate_variable_map()
      # return the deleted value
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
      setup_interface = Morpheus::SetupInterface.new({url:app_url, verify_ssl: (app_map[:insecure] != true)})
      check_json_response = nil
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
      rescue JSON::ParserError => err
        app_map[:status] = 'unrecognized'
        app_map[:last_check][:error] = err.message
      rescue RestClient::Exception => err
        app_map[:status] = 'http-error'
        app_map[:http_status] = err.response ? err.response.code : nil
        app_map[:last_check][:error] = err.message
        # fallback to /ping for older appliance versions (pre 2.10.5)
        begin
          Morpheus::Logging::DarkPrinter.puts "falling back to remote check via /ping ..." if Morpheus::Logging.debug?
          check_json_response = @setup_interface.ping()
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
      return app_map, check_json_response

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
