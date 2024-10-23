require 'morpheus/cli/cli_command'

# The morpheus setup command provides interaction with /api/setup
# This is initializing a fresh remote appliance.
# and checking the remote status and version.
class Morpheus::Cli::Setup
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RemoteHelper
  
  set_command_name :setup
  
  # register_subcommands :init

  # no authorization needed
  def connect(options={})
    @api_client = establish_remote_appliance_connection({:no_authorization => true, :skip_login => true}.merge(options))
    @setup_interface = @api_client.setup
  end

  def handle(args)
    #handle_subcommand(args)
    init(args)
  end

  # this is a wizard that walks through the /api/setup controller
  # it only needs to be used once to initialize a new appliance
  # def setup(args)
  def init(args)
    params, payload = {}, {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      #opts.banner = subcommand_usage()
      opts.banner = usage
      build_standard_add_options(opts, options, [:quiet, :auto_confirm])
      opts.on('--hubmode MODE','--hubmode MODE', "Choose an option for hub registration possible values are login, register, skip.") do |val|
        options[:hubmode] = val.to_s.downcase
      end
      opts.on('--license KEY', String, "License key to install") do |val|
        options[:license] = val
      end
      opts.on('--force','--force', "Force setup, make api request even if setup is unavailable.") do
        options[:force] = true
      end
      # todo: need all the other options here hub-username/password, account-name, username, password, email, etc.
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
    verify_args!(args:args, count:0, optparse:optparse)
    connect(options)
    exit_code, err = 0, nil
    # construct payload
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      payload.deep_merge!(parse_passed_options(options))

      # JD: This should just do a Remote.check_appliance() first... needs to work with --remote-url though.
      appliance_status_json = nil
      begin
        appliance_status_json = @setup_interface.get()
      rescue RestClient::SSLCertificateNotVerified => e
        @remote_appliance[:status] = 'ssl-error'
        @remote_appliance[:last_check] ||= {}
        @remote_appliance[:last_check][:error] = e.message
      rescue RestClient::Exception => e
        # pre 4.2.1 api would return HTTP 400 here, but with setupNeeded=false
        # so fallback to the old /api/setup/check
        # this could be in the interface itself..
        if e.response && (e.response.code == 400 || e.response.code == 404 || e.response.code == 401)
          Morpheus::Logging::DarkPrinter.puts "HTTP 400 from /api/setup, falling back to older /api/setup/check" if Morpheus::Logging.debug?
          begin
            appliance_status_json = @setup_interface.check()
          rescue RestClient::Exception => e2
            # err = e2.message || "Bad Request"
            begin
              appliance_status_json = JSON.parse(e2.response.to_s)
            rescue TypeError, JSON::ParserError => ex
              #puts "Failed to parse error response as json: #{ex}"
            end
          end
        end
        if appliance_status_json.nil?
          @remote_appliance[:status] = 'http-error'
          @remote_appliance[:last_check] ||= {}
          @remote_appliance[:last_check][:error] = e.message
        end
      end

      # my_terminal.execute("setup needed?")
      # theres a bug here with --remote-url :status == "unknown"
      # but hey, we got json back, so set status to "ready"
      if appliance_status_json
        @remote_appliance[:status] == 'ready'
      end
      remote_status_string = format_appliance_status(@remote_appliance, cyan)
      if appliance_status_json && appliance_status_json['setupNeeded'] == true
        # ok, setupNeeded
        # print_error cyan,"Setup is needed, status is #{remote_status_string}",reset,"\n"
      else
        if @remote_appliance[:status] == 'ssl-error'
          print_error cyan,"Setup unavailable, status is #{remote_status_string}","\n"
          print_error "Try passing the --insecure option.",reset,"\n"
          return 1, "setup unavailable"
        end
        if options[:force] != true
          print_error cyan,"Setup unavailable, status is #{remote_status_string}",reset,"\n"
          #print_error red, "#{appliance_status_json['msg']}\n", reset
          return 1, "setup unavailable"
        end
      end

      # retrieved hub.enabled and hub.url 
      hub_settings = appliance_status_json['hubSettings'] || appliance_status_json['hub'] || {}

      # store login/registration info in here, for prompt default values
      hub_info = nil
      print cyan
      print_h2 "Remote Setup | #{display_appliance(@appliance_name, @appliance_url)}"
      
      print cyan
      puts "It looks like you are the first one here, so let's begin."
      print reset, "\n"
      # print "\n"
      unless Morpheus::Cli::OptionTypes.confirm("Would you like to setup and initialize the remote appliance now?", options)  
        return 9, "aborted command"
      end
      print "\n"
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
          puts "* #{hub_action['name']} [#{hub_action['value']}]"
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
      # payload.deep_merge!(params)

      # print cyan
      #print_h1 "Morpheus Appliance Setup", [], options
      #print cyan
      #puts "Initializing remote appliance at URL: #{@appliance_url}"

      # Master Tenant
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
      print_h2 "Appliance Settings", options
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

      # License Key prompt
      print_h2 "License", options
      if options[:license]
        payload['licenseKey'] = options[:license].strip
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'licenseKey', 'fieldLabel' => 'License Key', 'type' => 'text', 'description' => "Enter a License Key to install now or leave blank to use a community license or install one manually later."}], options[:options])
        key = v_prompt['licenseKey']
        payload['licenseKey'] = key.strip if !key.to_s.strip.empty?
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
    print green,"Setup complete for remote #{display_appliance(@appliance_name, @appliance_url)}",reset,"\n"
    #print cyan, "You may now login with the command `login`.\n"
    # uh, just use Credentials.login(username, password, {save: true})
    cmd_res = Morpheus::Cli::Login.new.login(['--username', payload['username'], '--password', payload['password'], '-q'] + (options[:remote] ? ["-r",options[:remote]] : []))
    # print "\n"
    print cyan, "You are now logged in as the System Admin #{payload['username']}.\n"
    print reset
    #print "\n"

    if hubmode == 'skip'
      if ::Morpheus::Cli::OptionTypes::confirm("Would you like to install your License Key now?", options.merge({:default => true}))
        cmd_res = Morpheus::Cli::License.new.install([] + (options[:remote] ? ["-r",options[:remote]] : []))
        # license_is_valid = cmd_res != false
      end
    end

    if ::Morpheus::Cli::OptionTypes::confirm("Would you like to create the first group now?", options.merge({:default => true}))
      cmd_res = Morpheus::Cli::Groups.new.add(['--use'] + (options[:remote] ? ["-r",options[:remote]] : []))

      #print "\n"

      # if cmd_res !=
        if ::Morpheus::Cli::OptionTypes::confirm("Would you like to create the first cloud now?", options.merge({:default => true}))
          cmd_res = Morpheus::Cli::Clouds.new.add([] + (options[:remote] ? ["-r",options[:remote]] : []))
          #print "\n"
        end
      # end
    end
    print "\n",reset
    return exit_code, err
  end
 
end
