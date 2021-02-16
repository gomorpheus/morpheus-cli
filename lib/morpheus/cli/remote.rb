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
  include Morpheus::Cli::RemoteHelper

  register_subcommands :list, :add, :get, :update, :rename, :remove, :use, :unuse, :clone, :current, :view
  # remote setup and remote check
  # are now avaiable under ping and setup
  # they do the same thing
  register_subcommands :setup
  register_subcommands :check
  register_subcommands :'check-all' => :check_all
  register_subcommands :version => :version

  set_default_subcommand :list

  set_subcommands_hidden :setup # this is going away too

  def initialize()
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts={})
    # no authorization needed, do not verify a token or prompt for login
    @api_client = establish_remote_appliance_connection({:skip_verify_access_token => true, :skip_login => true}.merge(opts))
    @setup_interface = @api_client.setup
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    show_all_activity = false
    current_only = false
    do_check = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[search]")
      opts.on("-a",'--all', "Show all the appliance activity details") do
        show_all_activity = true
        options[:wrap] = true
      end
      opts.on("--current", "--current", "List only the active (current) appliance.") do
        current_only = true
      end
      opts.on("--check", "--check", "Check each appliance in the list to refresh their status, this may take a while.") do
        do_check = true
      end
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields])
      opts.footer = <<-EOT
List the configured remote appliances.
EOT
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    #connect(options)
    params.merge!(parse_list_options(options))
    appliances = ::Morpheus::Cli::Remote.load_all_remotes(params)
    # if appliances.empty?
    #   raise_command_error "You have no appliances configured. See the command `remote add`."
    # end
    if current_only
      appliances = appliances.select {|a| a[:active] }
    end
    if do_check
      # return here because it prints a list() too..
      return _check_all_appliances(options)
    end
    # mock json
    json_response = {"appliances" => appliances}
    # render
    exit_code, err = 0, nil
    render_response(json_response, options, "appliances") do
    
      if appliances.empty?
        if params[:phrase]
          print reset,"0 remotes matched '#{params[:phrase]}'", reset, "\n"
          print reset,"Try `remote add #{params[:phrase]}`", reset, "\n"
          return 0, nil # maybe exit non-zero when no records are found, could be nicer
        else
          warning_msg = "No remote appliances configured. See the command `remote add`."
          print yellow, warning_msg, reset, "\n"
          return 2, warning_msg
        end
      else
        title = "Morpheus Appliances"
        subtitles = parse_list_subtitles(options)
        subtitles << "Current" if current_only
        print_h1 title, subtitles, options

        columns = {
          "Name" => :name,
          "URL" => lambda {|it| it[:url] || it[:host] },
          "Status" => lambda {|it| format_appliance_status(it, cyan) },
          "Version" => lambda {|it| it[:build_version] ? "#{it[:build_version]}" : '' },
          "Appliance URL" => lambda {|it| it[:appliance_url] ? "#{it[:appliance_url]}" : '' },
          "Secure" => lambda {|it| format_boolean(it[:insecure] != true && (it[:url] || it[:host]).to_s.include?("https")) },
          "Active" => lambda {|it| it[:active] ? "Yes " + format_is_current() : "No" },
          #"Authenticated" => lambda {|it| format_boolean it[:authenticated] },
          "Username" => :username,
          # "Activity" => lambda {|it| get_appliance_session_blurbs(it).join("\n" + (' '*15)) },
          "Last Login" => lambda {|it| format_duration_ago(it[:last_login_at]) },
          #"Last Logout" => lambda {|it| format_duration_ago(it[:last_logout_at]) },
          "Last Success" => lambda {|it| format_duration_ago(it[:last_success_at]) },
          "Last Check" => lambda {|it| 
            check_str = ""
            if it[:last_check]
              check_timestamp = it[:last_check][:timestamp]
              check_status = it[:last_check][:http_status]
              if check_status
                if check_status == 200
                  # no need to show this
                else
                  check_status = check_status
                end
              end
              if check_timestamp
                check_duration_str = format_duration_ago(check_timestamp)
                # check_str = check_status ? "#{check_duration_str} (HTTP #{check_status})" : check_duration_str
                check_str = check_duration_str
              end
            else
              # check_str = "n/a"
            end
            check_str
          },
          "Response Time" => lambda {|it| format_duration_milliseconds(it[:last_check][:took]) rescue "" },
          "Error" => {display_method: lambda {|it| 
            error_str = it[:last_check] ? it[:last_check][:error].to_s : "" 
            error_str
          }, max_width: 30},
        }
        # when an active remote is in the list, add => prefix and padding to keep things aligned.
        # this is sucky, use arrays
        has_active_remote = appliances.find {|appliance| appliance[:active] }
        if has_active_remote
          columns.delete("Name")
          columns = {"   Name" => lambda {|it| it[:active] ? (bold + "=> #{it[:name]}" + reset + cyan) : "   #{it[:name]}" } }.merge(columns)
        end
        has_an_error = appliances.find {|appliance| appliance[:last_check][:error] rescue nil }
        if !has_an_error
          columns.delete("Error")
        end
        if show_all_activity != true
          columns.delete("Secure")
          columns.delete("Appliance URL")
          columns.delete("Active")
          columns.delete("Authenticated")
          columns.delete("Last Login") 
          columns.delete("Last Logout") 
          columns.delete("Last Success") 
          #columns.delete("Error")  # unless appliances.find {|appliance| appliance[:last_check][:error] rescue nil }
        else
          # always remove these columns because they are worthless
          columns.delete("Authenticated")
          columns.delete("Active")
          columns.delete("Last Success") 
        end
        # oops, table labels are upcase, but description list is not??, make them upcase here
        new_columns = {}
        columns.each {|k,v| new_columns[k.to_s.upcase] = v }
        columns = new_columns
        print as_pretty_table(appliances, columns, options)
        print reset
        print_results_pagination({size:appliances.size,total:appliances.size})
      end
      print reset, "\n"
    end
    return exit_code, err
  end

  def add(args)
    options, params, payload = {}, {}, {}
    new_appliance_map = {}
    use_it = nil
    secure = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage('[name] [url]')
      opts.on(nil, '--use [true|false]', "Start using remote right now. By default this is true if it's the first remote, otherwise false." ) do |val|
        use_it = (val == 'no' || val == 'off' || val.to_s == 'false')
        new_appliance_map[:active] = true
      end
      opts.on(nil, "--secure", "Prevent insecure HTTPS communication.  Default is true.") do
        secure = true
      end
      opts.on(nil, "--insecure", "Allow insecure HTTPS communication.  i.e. Ignore SSL errors. Default is false.") do
        secure = false
      end
      # ok, need to be able to pass every option supported by login() and setup()
      build_common_options(opts, options, [:options, :quiet])
      opts.footer = <<-EOT
Add a new remote to your morpheus client configuration.
[name] is required. A unique name for your appliance. eg. demo
[url] is required. The URL of your appliance eg. https://demo.morpheusdata.com
First, this inspects the remote url to check the appliance status and version.
If remote is ready, it will prompt to login, see the command `login`.
If remote is freshly installed, it will prompt to initialize the appliance, see the command `setup`.
The option --use can be included to start using the new remote right away.
The remote will be used by default if it is the first remote in the configuration.
The --quiet option can be used to to skip prompting.

EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, max:2, optparse:optparse)

    # payload = options[:payload] ? options[:payload] : {}
    # payload.deep_merge!(parse_passed_options(options))
    # # skip prompting when --payload is used
    # if options[:payload].nil?
    # end
    
    # load current appliances
    appliances = ::Morpheus::Cli::Remote.appliances

    new_appliance_name = args[0] ? args[0] : nil
    url = args[1] ? args[1] : nil

    # Name
    still_prompting = true
    while still_prompting do
      if args[0]
        new_appliance_name = args[0]
        still_prompting = false
      else
        if new_appliance_name.to_s.empty?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'A unique name for the remote Morpheus appliance. Example: local'}], options[:options])
          new_appliance_name = v_prompt['name']
        end
      end
      # for the sake of sanity
      if [:current, :all, :'remote-url'].include?(new_appliance_name.to_sym)
        raise_command_error "The specified remote appliance name '#{new_appliance_name}' is invalid."
        new_appliance_name = nil
      end
      # unique name
      existing_appliance = appliances[new_appliance_name.to_sym]
      if existing_appliance
        print_error red,"The specified remote appliance name '#{new_appliance_name}' already exists: #{display_appliance(existing_appliance[:name], (existing_appliance[:url]))}",reset,"\n"
        new_appliance_name = nil
      end
      if new_appliance_name
        still_prompting = false
      end
      if new_appliance_name.nil? && still_prompting == false
        return 1
      end
    end

    new_appliance_map[:name] = new_appliance_name.to_sym

    # URL
    still_prompting = true
    while still_prompting do
      if args[1]
        url = args[1]
        still_prompting = false
      else
        if !url
          default_url = nil
          # use Name: dev to get a happy default.
          # if new_appliance_name == "dev"
          if new_appliance_name == "local" || new_appliance_name == "localhost" || new_appliance_name == "dev"
            default_url = "http://localhost:8080"
          end
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'url', 'fieldLabel' => 'URL', 'type' => 'text', 'required' => true, 'description' => 'The URL of the remote Morpheus appliance. Example: https://10.0.2.2', 'defaultValue' => default_url}], options[:options])
          url = v_prompt['url']
        end
      end

      # strip whitespace from URL
      url = url.to_s.strip

      if url.to_s !~ /^https?\:\/\/.+/
        print_error red,"The specified remote appliance url '#{url}' is invalid.",reset,"\n"
        #still_prompting = true
        url = nil
      else
        still_prompting = false
      end
      if url.nil? && still_prompting == false
        return 1
      end
    end

    new_appliance_map[:url] = url

    # --insecure or --secure
    # Secure? (Ignore SSL errors)
    # secure is the default, 
    # try to only store insecure:false in the appliances config
    if url.to_s =~ /^https\:/ && secure.nil?
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'insecure', 'fieldLabel' => 'Insecure (Ignore SSL Errors)', 'type' => 'checkbox', 'required' => false, 'defaultValue' => false, 'description' => 'Allow insecure HTTPS communication, ignore SSL errors.'}], options[:options])
      if v_prompt['insecure'].to_s == 'true' || v_prompt['insecure'].to_s == 'on'
        new_appliance_map[:insecure] = true
      end
    elsif secure != nil
      new_appliance_map[:insecure] = !secure
    end
    
    # --use
    if use_it != nil
      if use_it
        new_appliance_map[:active] = true
      end
    else
      # if ::Morpheus::Cli::OptionTypes::confirm("Would you like to switch to using this remote now?", options.merge({default: appliances.empty?}))
      #   new_appliance_map[:active] = true
      # end
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'use', 'fieldLabel' => 'Use?', 'type' => 'checkbox', 'defaultValue' => appliances.empty?, 'description' => 'Start using this remote right away'}], options[:options])
      if v_prompt['use'].to_s == 'true' || v_prompt['use'].to_s == 'on'
        new_appliance_map[:active] = true
      end
    end

    # save it
    appliance = ::Morpheus::Cli::Remote.save_remote(new_appliance_name.to_sym, new_appliance_map)

    # refresh it (does /api/setup/check to refresh status and build
    # todo: this should happen in save eh?
    #Morpheus::Logging::DarkPrinter.puts "inspecting remote #{appliance[:name]} #{appliance[:url]}" if Morpheus::Logging.debug? && !options[:quiet]
    appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name.to_sym)

    # hit /setup/check api and update version and status
    if !options[:quiet]
      # print_green_success "Added remote #{new_appliance_name}, status is #{format_appliance_status(appliance)}"
      print cyan,"Added remote #{new_appliance_name}, status is #{format_appliance_status(appliance)}",reset,"\n"
    end

    appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name.to_sym)
    # if !options[:quiet]
    #   print cyan
    #   puts "Status: #{format_appliance_status(appliance)}"
    #   print reset
    # end
    # puts "refreshed appliance #{appliance.inspect}"
    # determine command exit_code and err
    exit_code, err = 0, nil
    if (appliance[:status] != 'ready' && appliance[:status] != 'fresh')
      exit_code = 1
      err = "remote status is #{appliance[:status]}"
    end

    # just skip prompting no prompt -q is used.
    if options[:quiet]
      return exit_code, err
    end
    # just skip prompting no prompt -N is used.
    if options[:no_prompt]
      return exit_code, err
    end

    # setup fresh appliance?
    if appliance[:status] == 'fresh'
      print cyan
      puts "It looks like this appliance needs to be setup. Starting setup ..."
      #return setup([new_appliance_name] + [Morpheus::Logging.debug? ? ["--debug"] : []])
      return Morpheus::Cli::Setup.new.handle(["-r", new_appliance_name] + (Morpheus::Logging.debug? ? ["--debug"] : []))
    end

    # only login if you are using this remote
    # maybe remote use should do the login prompting eh?
    # if appliance[:active] && appliance[:status] == 'ready'
    if appliance[:status] == 'ready'
      print reset
      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to login now?", options.merge({default: true}))
        login_result = ::Morpheus::Cli::Login.new.handle(["-r", appliance[:name].to_s])
        keep_trying = true
        if login_result == 0
          keep_trying = false
        end
        while keep_trying do
          if ::Morpheus::Cli::OptionTypes::confirm("Login attempt failed. Would you like to try again?", options.merge({default: true}))
            login_result = ::Morpheus::Cli::Login.new.handle(["-r", appliance[:name].to_s])
            if login_result == 0
              keep_trying = false
            end
          else
            keep_trying = false
          end
        end

      end

    else
      #puts "Status is #{format_appliance_status(appliance)}"
    end

    # print new appliance details
    print_h1 "Morpheus Appliance", [], options
    print cyan
    print format_remote_details(appliance, options)
    print reset, "\n"
    #_get(appliance[:name], {})

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
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :quiet])
      opts.on('-a', '--all', "Check all remotes.") do
        checkall = true
      end
      opts.footer = <<-EOT
Check the status of a remote appliance.
[name] is optional. This is the name of a remote.  Default is the current remote. Can be passed as 'all'. to perform remote check-all.
This makes a request to the remote url and updates the status and version.
EOT
    end
    optparse.parse!(args)
    if checkall == true
      return _check_all_appliances(options)
    end
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

  def version(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[remote]")
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :quiet])
      opts.footer = <<-EOT
Print version of remote appliance.
[name] is optional. This is the name of a remote.  Default is the current remote.
This makes a request to the configured appliance url and updates the status and version.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, max:1, optparse:optparse)
    #connect(options)
    # print version, default is current remote
    appliance_name = nil
    if args.count == 0
      appliance_name = 'current'
    elsif args.count == 1
      appliance_name = args[0]
    else
      raise_command_error "No current appliance, see the command `remote use`"
    end
    exit_code, err = 0, nil
    
    appliance = load_remote_by_name(appliance_name)
    appliance_name = appliance[:name]
    appliance_url = appliance[:url]

    # found appliance, now refresh it  
    # print "Checking remote url: #{appliance[:url]} ..."
    json_response = nil
    if options[:do_offline] == true
      json_response = {'appliance' => appliance}
    else
      appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    end

    # render
    render_response(json_response, options) do
    end
    # if options[:json] || options[:yml] || options[:csv] || options[:quiet]
    render_result = render_with_format(json_response, options)
    return exit_code if render_result

    build_version = appliance[:build_version]
    if build_version
      print cyan,build_version.to_s,reset,"\n"
      return 0
    else
      print yellow,"version unknown".to_s,reset,"\n"
      return 1
    end
    
  end

  def check(args)
    options = {}
    checkall = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :quiet])
      opts.on('-a', '--all', "Check all remotes.") do
        checkall = true
      end
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      opts.footer = <<-EOT
Check the status of a remote appliance.
[name] is optional. This is the name of a remote.  Default is the current remote. Can be passed as 'all'. to perform remote check-all.
This makes a request to the configured appliance url and updates the status and version.
EOT
    end
    optparse.parse!(args)
    if checkall == true
      return _check_all_appliances(options)
    end
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
      appliance = load_remote_by_name(appliance_name)
      appliance_name = appliance[:name]
      appliance_url = appliance[:url]

      # found appliance, now refresh it
      
      if options[:do_offline]
        json_response = {'appliance' => appliance} # mock payload
      else
        appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name.to_sym)
        json_response = {'appliance' => appliance} # mock payload
        appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
        # json_response = {'appliance' => appliance} # mock payload
      end
      # appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)

      if (appliance[:status] != 'ready' && appliance[:status] != 'fresh')
        exit_code = 1
        # err = appliance[:last_check] && appliance[:last_check][:error] ? appliance[:last_check][:error] : nil
      end

      render_response(json_response, options) do
        print_h1 "Morpheus Appliance", [], options
        print cyan
        print format_remote_details(appliance, options)
        print reset, "\n"
      end
      return exit_code, err
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
    #connect(options) # needed?
    _check_all_appliances(options)
  end
  
  def _check_all_appliances(options)
    start_time = Time.now
    # reresh all appliances and then display the list view
    id_list = ::Morpheus::Cli::Remote.appliances.keys # sort ?
    if id_list.size > 1
      print cyan
      puts "Checking #{id_list.size} remotes"
    elsif id_list.size == 1
      puts "Checking #{Morpheus::Cli::Remote.appliances.keys.first}"
    end
    id_list.each do |appliance_name|
      #print "."
      appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    end
    took_sec = (Time.now - start_time)
    print_green_success "Completed check of #{id_list.size} #{id_list.size == 1 ? 'remote' : 'remotes'} in #{format_duration_seconds(took_sec)}"
    
    if options[:quiet]
      return 0
    end
    list([])
    return 0
  end

  def rename(args)
    exit_code, err, options, params, payload = 0, nil, {}, {}, {}
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
    verify_args!(args:args, count:2, optparse:optparse)
    appliance_name = args[0].to_sym
    new_appliance_name = args[1].to_sym
    appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}', see the command `remote list`"
    end
    # don't allow overwrite yet
    matching_appliance = ::Morpheus::Cli::Remote.load_remote(new_appliance_name)
    if matching_appliance
      raise_command_error "Remote appliance already exists with the name '#{new_appliance_name}', see the command `, see the command `remote get #{new_appliance_name}`"
    end
    
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you want to rename remote '#{appliance_name}' to '#{new_appliance_name}'?", options)
      return 9, "aborted command"
    end
    # this does all the work
    ::Morpheus::Cli::Remote.rename_remote(appliance_name, new_appliance_name)

    print_green_success "Renamed remote #{appliance_name} to #{new_appliance_name}"
    # todo: just go ahead and refresh it now...
    # _check(appliance_name, {:quiet => true})
    # appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name)
    # print new appliance details
    _get(new_appliance_name, {})
    return 0, nil
  end

  def update(args)
    exit_code, err, options, params, payload = 0, nil, {}, {}, {}
    use_it = false
    is_insecure = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on("--name NAME", String, "Update the name of your remote appliance") do |val|
        params[:name] = val
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
    verify_args!(args:args, count:1, optparse:optparse)

    appliance_name = args[0].to_sym
    appliance = load_remote_by_name(appliance_name)
    appliance_name = appliance[:name]
    appliance_url = appliance[:url]

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
    # rename_remote() should be inside save_remote()
    if params[:name] && params[:name].to_s != appliance_name.to_s
      ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)
      ::Morpheus::Cli::Remote.rename_remote(appliance_name, params[:name])
      print_green_success "Updated remote #{appliance_name} (renamed #{params[:name]})"
      appliance_name = params[:name]
    else
      ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)
      print_green_success "Updated remote #{appliance_name}"
    end
    
    # todo: just go ahead and refresh it now...
    # _check(appliance_name, {:quiet => true})
    appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name)
    # print new appliance details
    _get(appliance[:name], {})
    return exit_code, err
  end

  def clone(args)
    exit_code, err, options, params, payload = 0, nil, {}, {}, {}
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[remote] [name]")
      # opts.on(nil, "--secure", "Prevent insecure HTTPS communication.  This is enabled by default") do
      #   params[:secure] = true
      # end
      # opts.on(nil, "--insecure", "Allow insecure HTTPS communication.  i.e. Ignore SSL errors.") do
      #   params[:insecure] = true
      # end
      opts.on(nil, '--use', "Make it the current appliance" ) do
        use_it = true
        params[:active] = true
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
Clone remote appliance configuratio, including any existing credentials.
[remote] is required. This is the name of an existing remote.
[name] is optional. This is the name of the new remote that will be created.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    

    appliance_name = args[0].to_sym
    appliance = load_remote_by_name(appliance_name)
    if !appliance
      raise_command_error "Remote appliance not found by the name '#{appliance_name}', see the command `remote list`"
    end

    new_appliance_name = args[1].to_sym
    matching_appliance = ::Morpheus::Cli::Remote.appliances[new_appliance_name.to_sym]
    if matching_appliance
      raise_command_error "Remote already exists with the name '#{matching_appliance[:name]}', see the command `remote get #{matching_appliance[:name]}`"
    end

    # ok clone it
    original_appliance = appliance
    appliance = original_appliance.clone
    appliance[:name] = new_appliance_name

    if params[:insecure]
      appliance[:insecure] = true
    elsif params[:secure]
      appliance.delete(:insecure)
    end
    if params[:url] || params[:host]
      appliance[:url] = params[:url] || params[:host]
      # appliance.delete(:host)
    end
    if use_it
      appliance[:active] = true
    end

    # save the new remote
    ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)
    # refresh it now?
    appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(new_appliance_name)

    # render
    if options[:quiet]
      return exit_code, err
    end
    print_green_success "Cloned remote #{original_appliance[:name]} to #{appliance[:name]}"
    # print new appliance details
    _get(appliance[:name], {})
    return exit_code, err
  end

  def get(args)
    exit_code, err, options, params, payload = 0, nil, {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-u', '--url', "Print only the url." ) do
        options[:url_only] = true
      end
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      build_common_options(opts, options, [:json,:yaml,:csv,:fields, :quiet])
      opts.footer = <<-EOT
Print details about the a remote appliance.
[name] is optional. This is the name of a remote. 
By default, the current appliance is used.
Returns an error if the specified remote is not found, or there is no current remote.
EOT
    end
    optparse.parse!(args)
    id_list = nil
    # verify_args!(args:args, min:1, optparse:optparse)
    if args.count == 0
      id_list = ['current']
    else
      id_list = parse_id_list(args)
    end
    #connect(options)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(appliance_name, options)
    exit_code, err = 0, nil
    if appliance_name == 'current'
      current_appliance = ::Morpheus::Cli::Remote.load_active_remote()
      if current_appliance.nil?
        #raise_command_error "No current appliance, see the command `remote use`"
        unless options[:quiet]
          print yellow, "No current appliance, see the command `remote use`", reset, "\n"
        end
        return 1, "No current appliance"
      end
    end
    appliance = load_remote_by_name(appliance_name)
    appliance_name = appliance[:name]
    appliance_url = appliance[:url]

    # refresh remote status and version by default
    # should json just be appliance instead maybe?
    json_response = nil
    if options[:do_offline]
      json_response = {'appliance' => appliance} # mock payload
    else
      appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance_name.to_sym)
      json_response = {'appliance' => appliance} # mock payload
    end

    # render
    render_response(json_response, options) do
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

      print_h1 "Morpheus Appliance", [], options
      print cyan
      print format_remote_details(appliance, options)
      print reset, "\n"
    end
    return exit_code, err
    
  end

  def view(args)
    options = {}
    path = "/"
    no_auth = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--path PATH', String, "Specify a path to load. eg '/logs'" ) do |val|
        path = val
      end
      opts.on('--no-auth PATH', String, "Do not attempt to login with access token." ) do |val|
        no_auth = true
      end
      build_common_options(opts, options, [:dry_run])
      opts.footer = <<-EOT
View remote appliance in a web browser.
[name] is optional. This is the name of a remote.  Default is the current remote.
This will automatically login with the current access token.
EOT
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse)
    if args.count == 0
      id_list = ['current']
      #raise_command_error "wrong number of arguments, expected 1-N and got 0\n#{optparse}"
    else
      id_list = parse_id_list(args)
    end
    #connect(options)
    return run_command_for_each_arg(id_list) do |arg|
      _view_appliance(arg, path, no_auth, options)
    end
  end

  def _view_appliance(appliance_name, path, no_auth, options)
    appliance = load_remote_by_name(appliance_name)
    appliance_name = appliance[:name]
    appliance_url = appliance[:url]
    if appliance_url.to_s.empty?
      raise_command_error "Remote appliance does not have a url?"
    end
    path = path.to_s.empty? ? "/" : path
    if path[0].chr != "/"
      path = "/#{path}"
    end
    wallet = ::Morpheus::Cli::Credentials.new(appliance_name, nil).load_saved_credentials()
    # try to auto login if we have a token
    link = "#{appliance_url}#{path}"
    if no_auth == false
      if wallet && wallet['access_token']
        link = "#{appliance_url}/login/oauth-redirect?access_token=#{wallet['access_token']}\\&redirectUri=#{path}"
      end
    end

    if options[:dry_run]
      puts Morpheus::Util.open_url_command(link)
      return 0
    end
    return Morpheus::Util.open_url(link)
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
    verify_args!(args:args, min:1, optparse:optparse)
    id_list = parse_id_list(args)
    #connect(options)
    # verify they all exist first, this a cheap lookup and raises and error if not found
    id_list.each do |remote_id|
      found_remote = load_remote_by_name(remote_id)
      return 1, "Remote appliance not found by the name '#{remote_id}', see the command `remote list`" if found_remote.nil?
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete #{id_list.size == 1 ? 'remote' : id_list.size.to_s + ' remotes'}: #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _remove_appliance(arg, options)
    end
  end

  def _remove_appliance(appliance_name, options)
    if ::Morpheus::Cli::Remote.appliances[appliance_name.to_sym].nil?
      raise_command_error "Remote does not exist with name '#{appliance_name.to_s}'"
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

def remove_all(args)
    options = {}
    checkall = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:auto_confirm, :quiet])
      opts.footer = <<-EOT
Remove all remote appliances, clearing the client configuration.
This clears all the configured remotes and credentials.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, count:0, optparse:optparse)
    connect(options) # needed?
    _remove_all_appliances(options)
  end
  
  def _remove_all_appliances(options)
    exit_code, err = 0, nil
    all_appliance_names = ::Morpheus::Cli::Remote.appliances.keys.size
    if all_appliance_names.empty?
      if options[:quiet] != true
        print_green_success "No remotes found, nothing to remove"
        return 0, nil
      end
    end
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you want to remove all of your remotes (#{all_appliance_names.size})?", options)
      return 9, "aborted command"
    end
    # ok, do it
    deleted_list = ::Morpheus::Cli::Remote.delete_all_remotes()

    # render
    if options[:quiet]
      return exit_code, err
    end
    if all_appliance_names.size == 1
      print_green_success "Removed 1 remote (#{all_appliance_names.join(', ')})"
    else
      print_green_success "Removed 1 remote () "
    end
    #list([])
    return exit_code, err
  end

  def use(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
[name] is required. This is the name of a remote to begin using.
Start using a remote, making it the active (current) remote appliance.
This switches the remote context of your client configuration for all subsequent commands.
It is important to always be aware of the context your commands are running in.
The command `remote current` will return the current remote information.
Instead of using an active remote, the -r option can be specified with each command.

It is recommeneded to set a custom prompt to show the current remote name.
For example, add the following to your .morpheusrc file:

  # set your shell prompt to display the current username and remote
  set-prompt "%green%username%reset@%magenta%remote %cyanmorpheus> %reset"

EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, count:1, optparse:optparse)
    exit_code, err = 0, nil
    # connect()
    current_appliance_name, current_appliance_url = @appliance_name, @appliance_url
    current_appliance = ::Morpheus::Cli::Remote.load_active_remote()
    if current_appliance
      current_appliance_name, current_appliance_url = current_appliance[:name], current_appliance[:url]
    end
    
    # current_appliance_name, current_appliance_url = @appliance_name, @appliance_url 
    appliance_name = args[0].to_sym
    appliance = load_remote_by_name(appliance_name)
    # appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
    # if !appliance
    #   raise_command_error "Remote not found by the name '#{appliance_name}', see the command `remote list`"
    # end

    # appliance = ::Morpheus::Cli::Remote.set_active_appliance(appliance_name)
    appliance[:active] = true
    appliance = ::Morpheus::Cli::Remote.save_remote(appliance_name, appliance)

    if options[:quiet]
      return 0
    end

    if current_appliance_name.to_s == appliance_name.to_s
      print_green_success "Using remote #{display_appliance(appliance[:name], appliance[:url])}"
    else
      print_green_success "Using remote #{display_appliance(appliance[:name], appliance[:url])}"
    end
    
    # recalculate session variables
    ::Morpheus::Cli::Remote.recalculate_variable_map()

    # could just do this
    # return _get(appliance_name, options)

    # ok need to refresh here unless --offline
    # refresh status and version
    # maybe just make json_response = appliance here
    unless options[:do_offline]
      appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance[:name])
    end
    # return list([])
    return exit_code, err
  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "Stop using the current remote appliance.\n"
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    verify_args!(args:args, count:0, optparse:optparse)
    #connect(options)
    exit_code, err = 0, nil
    @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    if !@appliance_name
      print reset,"You are not using any remote appliance",reset,"\n"
      return 0
    end
    Morpheus::Cli::Remote.clear_active_appliance()
    print_green_success "Stopped using remote #{display_appliance(@appliance_name, @appliance_url)}"
    # recalculate session variables
    ::Morpheus::Cli::Remote.recalculate_variable_map()
    # return list([])
    return exit_code, err
  end

  def current(args)
    options = {}
    name_only = false
    url_only = false
    version_only = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.on( '-n', '--name', "Print only the name." ) do
        name_only = true
      end
      opts.on( '-u', '--url', "Print only the url." ) do
        url_only = true
      end
      opts.on( '-v', '--version', "Print only the build version." ) do
        version_only = true
      end
      opts.on('--offline', '--offline', "Do this offline without an api request to refresh the remote appliance status.") do
        options[:do_offline] = true
      end
      build_common_options(opts, options, [:json,:yaml,:csv,:fields, :quiet])
      opts.footer = <<-EOT
Print details about the current remote appliance.
This behaves the same as `remote get current`.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, count:0, optparse:optparse)
    #connect(options)

    current_appliance = ::Morpheus::Cli::Remote.load_active_remote()
    if current_appliance.nil?
      #raise_command_error "No current appliance, see the command `remote use`"
      unless options[:quiet]
        print yellow, "No current appliance, see the command `remote use`", reset, "\n"
      end
      return 1, "No current appliance"
    end

    # this does the same thing
    #return _get("current", options)
    appliance = current_appliance
    #appliance = load_remote_by_name("current")
    #appliance = @remote_appliance
    exit_code, err = 0, nil
    if appliance.nil?
      raise_command_error "no current remote appliance, see command `remote add`."
    end

    # ok need to refresh here unless do_offline
    # refresh status and version
    # maybe just make json_response = appliance here
    json_response = nil
    if options[:do_offline]
      json_response = {'appliance' => appliance} # mock payload
    else
      appliance, json_response = ::Morpheus::Cli::Remote.refresh_remote(appliance[:name])
      json_response = {'appliance' => appliance} # mock payload
    end
    # could set exit_code if appliance[:build_version].nil?
    render_response(json_response, options) do
      if name_only && url_only
        #print cyan, display_appliance(appliance[:name], appliance[:url]),"\n",reset
        print cyan, appliance[:name], " ", appliance[:url],"\n",reset
      elsif name_only
        print cyan, appliance[:name],"\n",reset
      elsif url_only
        print cyan, appliance[:url],"\n",reset
      elsif version_only
        print cyan, appliance[:build_version],"\n",reset
      else
        print_h1 "Morpheus Appliance", [], options
        print cyan
        print format_remote_details(appliance, options)
        print reset, "\n"
      end
    end
    return exit_code, err
  end

  
  # This moved to the SetupCommand
  def setup(args)
    print_error yellow,"[DEPRECATED] The command `remote setup` is deprecated. It has been replaced by `setup`.",reset,"\n"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet])
      opts.on('--hubmode MODE','--hubmode MODE', "Choose an option for hub registration possible values are login, register, skip.") do |val|
        options[:hubmode] = val.to_s.downcase
      end
      opts.footer = <<-EOT
Setup a fresh remote appliance, initializing it.
First, this checks if setup is available, and returns an error if not.
Then it prompts to create the master tenant and admin user.
If Morpheus Hub registration is enabled, you may login or register to retrieve a license key,
or you can pass `--hubmode skip`.
This is only available on a new, freshly installed remote appliance,
and it may only be executed successfully one time.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max:1)
    # just invoke the setup command.
    # for this to work, the argument [remote] must be the first argument.
    cmd_args = []
    remote_name = nil
    if args[0]
      remote_name = args.shift
      # cmd_args = cmd_args + ["-r",remote_name, args]
      cmd_args = args + ["-r",remote_name, args]
    end
    return Morpheus::Cli::Setup.new.handle(cmd_args)
  end

  def load_remote_by_name(appliance_name, allow_current=true)
    appliance = nil
    if appliance_name.to_s == "current" && allow_current
      appliance = ::Morpheus::Cli::Remote.load_active_remote()
      if !appliance
        raise_command_error "No current appliance, see the command `remote use`"
      end
    else
      appliance = ::Morpheus::Cli::Remote.load_remote(appliance_name)
      if !appliance
        raise_command_error "Remote not found by name '#{appliance_name}', see the command `remote list`"
      end
    end
    return appliance
  end

  def format_remote_details(appliance, options={})
    columns = {
      #"Name" => :name,
      "Name" => lambda {|it| it[:name].to_s },
      #"Name" => lambda {|it| it[:active] ? "#{it[:name]} #{bold}(current)#{reset}#{cyan}" : it[:name] },
      "URL" => lambda {|it| it[:url] || it[:host] },
      #"Status" => lambda {|it| format_appliance_status(it, cyan) },
      "Version" => lambda {|it| it[:build_version] ? "#{it[:build_version]}" : '' },
      "Appliance URL" => lambda {|it| it[:appliance_url] ? "#{it[:appliance_url]}" : '' },
      "Secure" => lambda {|it| format_appliance_secure(it) },
      "Active" => lambda {|it| it[:active] ? "Yes " + format_is_current() : "No" },
      # "Active" => lambda {|it| format_boolean(it[:active]) },
      #"Authenticated" => lambda {|it| format_boolean it[:authenticated] },
      "Username" => :username,
      # "Activity" => lambda {|it| get_appliance_session_blurbs(it).join("\n" + (' '*15)) },
      "Last Login" => lambda {|it| format_duration_ago(it[:last_login_at]) },
      #"Last Logout" => lambda {|it| format_duration_ago(it[:last_logout_at]) },
      "Last Success" => lambda {|it| format_duration_ago(it[:last_success_at]) },
      "Last Check" => lambda {|it| 
        check_timestamp = nil
        if it[:last_check] && it[:last_check][:timestamp]
          check_timestamp = it[:last_check][:timestamp]
        end
        check_status = nil
        if it[:last_check] && it[:last_check][:http_status]
          check_status = it[:last_check][:http_status]
        end
        if check_timestamp
          format_duration_ago(check_timestamp) # + (check_status ? " (HTTP #{check_status})" : "")
        else
          ""
        end
      },
      "Response Time" => lambda {|it| format_duration_milliseconds(it[:last_check][:took]) rescue "" },
      "Status" => lambda {|it| format_appliance_status(it, cyan) },
      "Error" => lambda {|it| 
        error_str = it[:last_check] ? it[:last_check][:error] : "" 
        # meh no need to show http status, :error explains it well enough
        # check_status = it[:last_check] ? it[:last_check][:http_status] : nil
        # if check_status && check_status != 200
        #   #"(HTTP #{check_status}) #{error_str}"
        # else
        #   error_str
        # end
        error_str
      },

    }
    if appliance[:last_success_at].nil?
      columns.delete("Last Success") 
    else
      columns.delete("Last Success") 
    end
    if appliance[:last_check].nil? || appliance[:last_check][:error].nil?
      columns.delete("Error") 
    end
    return as_description_list(appliance, columns, options)
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
      if @@appliance_config.nil?
        @@appliance_config
        @@appliance_config = load_appliance_file
        # fix things right away, replace deprecated :host with :url
        @@appliance_config.each do |app_name, appliance|
          host = appliance.delete(:host)
          if host && appliance[:url].to_s.empty?
            appliance[:url] = host
          end
        end
      end
      return @@appliance_config
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
        # :url used to be stored as :host
        if sort_key == :url || sort_key == :host
          all_appliances = all_appliances.sort {|a,b| (a[:url] || a[:host]).to_s <=> (b[:url] || b[:host]).to_s }
        elsif sort_key
          all_appliances = all_appliances.sort {|a,b| a[sort_key].to_s <=> b[sort_key].to_s }
        end
        if params['direction'] == 'desc'
          all_appliances.reverse!
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
      # need an app_name to save it
      if app_name.to_s.empty?
        puts "skipped save of remote with a blank name"
        return nil
      end
      # in case a temporary config gets passed in here, do not save it.. this should be avoided though
      if app_map[:temporary]
        puts "skipped save of temporary remote '#{app_name}'"
        return nil
      end
      app_name = app_name.to_sym
      # it's probably better to use load_appliance_file() here instead
      cur_appliances = self.appliances #.clone
      cur_appliances[app_name] = app_map
      #cur_appliances[app_name] ||= {:status => "unknown", :error => "Bad configuration. Missing url. See 'remote update --url'" }
      cur_appliances[app_name] ||= {:status => "unknown"}
      # :host is gone, use :url please
      if cur_appliances[app_name][:host]
        cur_appliances[app_name][:url] = cur_appliances[app_name].delete(:host)
      end
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
        print_red_alert "Remote not found by the name '#{app_name}', see the command `remote list`"
        #print "Did you mean one of these commands: #{suggestions.join(', ')?", reset, "\n"
        return nil
      end
      if cur_appliances[new_app_name]
        print_red_alert "A remote already exists with name '#{new_app_name}', see the command `remote get #{new_app_name}`"
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

    def delete_all_remotes()
      deleted_list = []
      self.appliances.each do |app_name, appliance|
        deleted_list << delete_remote(app_name)
      end
      # self.appliances = {}
      # Morpheus::Cli::Remote.save_appliances({})
      # recalculate_variable_map()
      # return deleted_list
      return self.appliances
    end

    # refresh_remote makes an api request to the configured appliance url
    # and updates the appliance's build version, status and last_check attributes
    def refresh_remote(app_name, params={}, timeout=5)
      app_name = app_name.to_sym
      cur_appliances = self.appliances
      appliance = cur_appliances[app_name] || {}
      appliance_url = (appliance[:url] || appliance[:host]).to_s
      if !appliance_url
        raise "appliance config is missing url!" # should not need this
      end
      # todo: this insecure flag needs to applied everywhere now tho..
      if appliance[:insecure]
        Morpheus::RestClient.enable_ssl_verification = false
        # Morpheus::RestClient.enable_http = true
      end
      err = nil
      json_response = nil
      # make request to /api/setup/check
      # and update appliance :status, :build_version, :last_check{}
      if appliance_url.to_s.empty?
        err = "no url specified"
        # wtf, no url...
        return appliance, json_response
      else
        setup_interface = Morpheus::SetupInterface.new({url:appliance_url, verify_ssl: (appliance[:insecure] != true), timeout: timeout})
        start_time = Time.now
        begin
          json_response = setup_interface.check(params)
        rescue => ex
          err = ex
        ensure
          took_sec = Time.now - start_time
        end
        
        # save and update appliance info
        return save_remote_last_check(appliance, json_response, err, took_sec)
      end
    end

    # save the app status and last request information
    # looks for json_response like /setup/check and /ping
    def save_remote_last_check(appliance, json_response, err=nil, took_sec=nil)
      #puts "save_remote_last_check: #{appliance}, #{json_response}"
      app_name = appliance[:name] ? appliance[:name].to_sym : nil
      cur_appliances = self.appliances
      app_map = appliance
      app_url = (app_map[:url] || app_map[:host]).to_s
      if !app_url
        raise "appliance config is missing url!"
      end
      
      # only change stuff that was contained in the response
      # this stores things under the context last_check
      appliance[:last_check] = {}
      appliance[:last_check][:success] = json_response.nil?
      appliance[:last_check][:timestamp] = Time.now.to_i
      appliance[:last_check][:http_status] = json_response ? 200 : nil
      if took_sec
        # store in ms
        appliance[:last_check][:took] = (took_sec.to_f*1000).round
      end
      if json_response
        if json_response.key?('applianceUrl')
          appliance[:appliance_url] = json_response['applianceUrl']
        end
        if json_response.key?('buildVersion')
          appliance[:build_version] = json_response['buildVersion']
          appliance[:status] = 'ready'
          appliance[:last_check][:success] = true
          # consider bumping this after every successful api command
          appliance[:last_success_at] = Time.now.to_i
          appliance.delete(:error)
        end
        if json_response.key?('setupNeeded')
          if json_response['setupNeeded'] == true
            appliance[:setup_needed] = true
            appliance[:status] = 'fresh'
          else
            appliance.delete(:setup_needed)
          end
        end
      else
        # no response body eh?
        appliance[:last_check][:success] = false
        appliance[:last_check][:error] = "Invalid api response"
        appliance[:status] = 'error'
      end
      # handle error
      if err
        case(err)
        when SocketError
          appliance[:status] = 'unreachable'
          appliance[:last_check][:http_status] = nil
          appliance[:last_check][:error] = err.message
        when RestClient::Exceptions::Timeout
          # print_rest_exception(e, options)
          # exit 1
          appliance[:status] = 'http-timeout'
          appliance[:last_check][:http_status] = nil
        when Errno::ECONNREFUSED
          appliance[:status] = 'net-error'
          appliance[:last_check][:error] = err.message
        when OpenSSL::SSL::SSLError
          appliance[:status] = 'ssl-error'
          appliance[:last_check][:error] = err.message
        when JSON::ParserError
          appliance[:status] = 'unrecognized'
          appliance[:last_check][:error] = err.message
        when RestClient::Exception
          appliance[:status] = 'http-error'
          # appliance[:http_status] = err.response ? err.response.code : nil
          appliance[:last_check][:http_status] = err.response ? err.response.code : nil
          appliance[:last_check][:error] = err.message
          # if err.response.code == 404
          #   appliance[:status] = 'ready' # 'ok'
          #   Morpheus::Logging::DarkPrinter.puts "ping failed but it is ready" if Morpheus::Logging.debug?
          # end
        else
          appliance[:status] = 'error' # err.class.to_s.dasherize
          appliance[:last_check][:error] = err.message
        end
      end

      # save to disk
      save_remote(app_name, appliance)
      
      # return map and response
      return appliance, json_response
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
