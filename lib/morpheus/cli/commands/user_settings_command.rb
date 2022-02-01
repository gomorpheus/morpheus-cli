require 'morpheus/cli/cli_command'

class Morpheus::Cli::UserSettingsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'user-settings'

  register_subcommands :get, :update, :'update-avatar', :'remove-avatar', :'view-avatar', :'update-desktop-background', :'remove-desktop-background', :'view-desktop-background', :'regenerate-access-token', :'clear-access-token', :'list-clients'
  
  set_default_subcommand :get
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @user_settings_interface = @api_client.user_settings
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
  end

  def handle(args)
    handle_subcommand(args)
  end

  def get(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = <<-EOT
Get user settings. 
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    if options[:user]
      user = find_user_by_username_or_id(nil, options[:user], {global:true})
      return 1 if user.nil?
      params['userId'] = user['id']
    end
    params.merge!(parse_list_options(options))
    @user_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @user_settings_interface.dry.get(params)
      return
    end
    json_response = @user_settings_interface.get(params)
    
    render_response(json_response, options) do

      user_settings = json_response['user'] || json_response['userSettings']
      access_tokens = user_settings['accessTokens'] || json_response['accessTokens'] || json_response['apiAccessTokens'] || []

      print_h1 "User Settings"
      print cyan
      description_cols = {
        #"ID" => lambda {|it| it['id'] },
        "ID" => lambda {|it| it['id'] },
        "Username" => lambda {|it| it['username'] },
        "First Name" => lambda {|it| it['firstName'] },
        "Last Name" => lambda {|it| it['lastName'] },
        "Email" => lambda {|it| it['email'] },
        "Avatar" => lambda {|it| it['avatar'] ? it['avatar'].split('/').last : '' },
        "Notifications" => lambda {|it| format_boolean(it['receiveNotifications']) },
        "Linux Username" => lambda {|it| it['linuxUsername'] },
        "Linux Password" => lambda {|it| it['linuxPassword'] },
        "Linux Key Pair" => lambda {|it| it['linuxKeyPairId'] },
        "Windows Username" => lambda {|it| it['windowsUsername'] },
        "Windows Password" => lambda {|it| it['windowsPassword'] },
        "Default Group" => lambda {|it| it['defaultGroup'] ? it['defaultGroup']['name'] : '' },
        "Default Cloud" => lambda {|it| it['defaultCloud'] ? it['defaultCloud']['name'] : '' },
        "Default Persona" => lambda {|it| it['defaultPersona'] ? it['defaultPersona']['name'] : '' },
        "Desktop Background" => lambda {|it| it['desktopBackground'] ? it['desktopBackground'].split('/').last : '' },
        "2FA Enabled" => lambda {|it| it['isUsing2FA'].nil? ? '' : format_boolean(it['isUsing2FA']) },
      }
      print_description_list(description_cols, user_settings)      

      if access_tokens && !access_tokens.empty?
        print_h2 "API Access Tokens"
        cols = {
          #"ID" => lambda {|it| it['id'] },
          "CLIENT ID" => lambda {|it| it['clientId'] },
          "USERNAME" => lambda {|it| it['username'] },
          "ACCESS TOKEN" => lambda {|it| it['maskedAccessToken'] },
          "REFRESH TOKEN" => lambda {|it| it['maskedRefreshToken'] },
          "EXPIRATION" => lambda {|it| format_local_dt(it['expiration']) },
          "TTL" => lambda {|it| it['expiration'] ? (format_duration(it['expiration']) rescue '') : '' }
        }
        print cyan
        puts as_pretty_table(access_tokens, cols)
      else
        #print "\n"
        print cyan, "\n", "No API access tokens found", "\n\n"
      end
      
      print reset #, "\n"
    end
    return 0, nil
  end


  def update(args)
    options = {}
    params = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_option_type_options(opts, options, update_user_settings_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update user settings.
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    if options[:user]
      user = find_user_by_username_or_id(nil, options[:user], {global:true})
      return 1 if user.nil?
      params['userId'] = user['id']
    end

    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'user' => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_user_settings_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # upload requires multipart instead of json
      if params['avatar']
        params['avatar'] = File.new(File.expand_path(params['avatar']), 'rb')
        payload[:multipart] = true
      end
      if params['desktopBackground']
        params['desktopBackground'] = File.new(File.expand_path(params['desktopBackground']), 'rb')
        payload[:multipart] = true
      end
      # userId goes in query string, not payload...
      query_params['userId'] = params.delete('userId') if params.key?('userId')
      payload.deep_merge!({'user' => params})
      if payload['user'].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end

    @user_settings_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @user_settings_interface.dry.update(payload, query_params)
      return
    end
    json_response = @user_settings_interface.update(payload, query_params)
    render_response(json_response, options) do
      print_green_success "Updated user settings"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (query_params['userId'] ? ['--user-id', query_params['userId'].to_s] : [])
      get(get_args)
    end
    return 0, nil
    
  end

  def update_avatar(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[file]")
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Update avatar profile image.
[file] is required. This is the local path of a file to upload [png|jpg|svg].
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    filename = File.expand_path(args[0].to_s)
    image_file = nil
    if filename && File.file?(filename)
      # maybe validate it's an image file? [.png|jpg|svg]
      image_file = File.new(filename, 'rb')
    else
      # print_red_alert "File not found: #{filename}"
      puts_error "#{Morpheus::Terminal.angry_prompt}File not found: #{filename}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.update_avatar(image_file, params)
        return
      end
      json_response = @user_settings_interface.update_avatar(image_file, params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Updated avatar"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_avatar(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Remove avatar profile image.
[file] is required. This is the local path of a file to upload [png|jpg|svg].
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.remove_avatar(params)
        return
      end
      json_response = @user_settings_interface.remove_avatar(params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Removed avatar"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def view_avatar(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:remote])
      opts.footer = <<-EOT
View avatar profile image.
This opens the avatar image url with a web browser.
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      json_response = @user_settings_interface.get(params)
      user_settings = json_response['user'] || json_response['userSettings']
      
      if user_settings['avatar']
        link = user_settings['avatar']
        if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
          system "start #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /darwin/
          system "open #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
          system "xdg-open #{link}"
        end
        return 0, nil
      else
        print_error red,"No avatar image found.",reset,"\n"
        return 1
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update_desktop_background(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[file]")
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Update desktop background image used in the VDI persona.
[file] is required. This is the local path of a file to upload [png|jpg|svg].
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    filename = File.expand_path(args[0].to_s)
    image_file = nil
    if filename && File.file?(filename)
      # maybe validate it's an image file? [.png|jpg|svg]
      image_file = File.new(filename, 'rb')
    else
      # print_red_alert "File not found: #{filename}"
      puts_error "#{Morpheus::Terminal.angry_prompt}File not found: #{filename}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.update_desktop_background(image_file, params)
        return
      end
      json_response = @user_settings_interface.update_desktop_background(image_file, params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Updated desktop background"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove_desktop_background(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Remove desktop background image.
[file] is required. This is the local path of a file to upload [png|jpg|svg].
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.remove_desktop_background(params)
        return
      end
      json_response = @user_settings_interface.remove_desktop_background(params)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Removed desktop background"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def view_desktop_background(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:remote])
      opts.footer = <<-EOT
View desktop background image.
This opens the desktop background image url with a web browser.
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      json_response = @user_settings_interface.get(params)
      user_settings = json_response['user'] || json_response['userSettings']
      
      if user_settings['desktopBackground']
        link = user_settings['desktopBackground']
        if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
          system "start #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /darwin/
          system "open #{link}"
        elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
          system "xdg-open #{link}"
        end
        return 0, nil
      else
        print_error red,"No desktop background image found.",reset,"\n"
        return 1
      end
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def regenerate_access_token(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client-id]")
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Regenerate API access token for a specific client.
[client-id] is required. This is the id of an api client.
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    params['clientId'] = args[0]
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      payload = {}
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.regenerate_access_token(params, payload)
        return
      end
      json_response = @user_settings_interface.regenerate_access_token(params, payload)
      new_access_token = json_response['access_token'] || json_response['token']
      # update credentials if regenerating cli token
      if params['clientId'] == Morpheus::APIClient::CLIENT_ID
        if params['userId'].nil? # should check against current user id
          if new_access_token
            # this sux, need to save refresh_token too.. just save to wallet and refresh shell maybe?
            login_opts = {:remote_token => new_access_token}
            login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(login_opts)
          end
        end
      end
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      print_green_success "Regenerated #{params['clientId']} access token: #{new_access_token}"
      get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def clear_access_token(args)
    raw_args = args
    options = {}
    params = {}
    client_id = nil
    all_clients = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client-id]")
      opts.on("--all", "--all", "Clear tokens for all Client IDs instead of a specific client.") do
        all_clients = true
      end
      # opts.on("--client-id", "Client ID. eg. morph-api, morph-cli") do |val|
      #   params['clientId'] = val.to_s
      # end
      opts.on("-u", "--user USER", "User username or ID") do |val|
        options[:user] = val.to_s
      end
      opts.on("--user-id ID", String, "User ID") do |val|
        params['userId'] = val.to_s
      end
      #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Clear API access token for a specific client.
[client-id] or --all is required. This is the id of an api client.
Done for the current user by default, unless a user is specified with the --user option.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 1 || (args.count == 0 && all_clients == false)
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      params['clientId'] = args[0]
    end
    if params['clientId'] == 'all'
      params.delete('clientId')
      all_clients = true
      # clears all when clientId is omitted, no api parameter needed.
    end
    begin
      if options[:user]
        user = find_user_by_username_or_id(nil, options[:user], {global:true})
        return 1 if user.nil?
        params['userId'] = user['id']
      end
      payload = {}
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.clear_access_token(params, payload)
        return
      end
      json_response = @user_settings_interface.clear_access_token(params, payload)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      new_access_token = json_response['token']
      # update credentials if regenerating cli token
      # if params['clientId'] == Morpheus::APIClient::CLIENT_ID
      #   logout_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout
      # end
      success_msg = "Success"
      if all_clients
        success_msg = "Cleared all access tokens"
      else
        success_msg = "Cleared #{params['clientId']} access token"
      end
      if params['userId']
        success_msg << " for user #{params['userId']}"
      end
      print_green_success success_msg
      if params['clientId'] == Morpheus::APIClient::CLIENT_ID
        if params['userId'].nil? # should check against current user id
          print yellow,"Your current access token is no longer valid, you will need to login again.",reset,"\n"
        end
      end
      # get_args = [] + (options[:remote] ? ["-r",options[:remote]] : []) + (params['userId'] ? ['--user-id', params['userId'].to_s] : [])
      # get(get_args)
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_clients(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      # opts.on("-u", "--user USER", "User username or ID") do |val|
      #   options[:user] = val.to_s
      # end
      # opts.on("--user-id ID", String, "User ID") do |val|
      #   params['userId'] = val.to_s
      # end
      # #opts.add_hidden_option('--user-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = <<-EOT
List available api clients.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      # if options[:user]
      #   user = find_user_by_username_or_id(nil, options[:user], {global:true})
      #   return 1 if user.nil?
      #   params['userId'] = user['id']
      # end
      params.merge!(parse_list_options(options))
      @user_settings_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.available_clients(params)
        return
      end
      json_response = @user_settings_interface.available_clients(params)
      if options[:json]
        puts as_json(json_response, options, "clients")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "clients")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['clients'], options)
        return 0
      end

      clients = json_response['clients'] || json_response['apiClients']
      print_h1 "Morpheus API Clients"
      columns = {
        "CLIENT ID" => lambda {|it| it['clientId'] },
        "NAME" => lambda {|it| it['name'] },
        "TTL" => lambda {|it| it['accessTokenValiditySeconds'] ? "#{it['accessTokenValiditySeconds']}" : '' },
        "DURATION" => lambda {|it| it['accessTokenValiditySeconds'] ? (format_duration_seconds(it['accessTokenValiditySeconds']) rescue '') : '' },
        # "USABLE" => lambda {|it| format_boolean(it['usable']) }
      }
      print cyan
      puts as_pretty_table(clients, columns)
      print reset #, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  protected

  def update_user_settings_option_types
    [
      # todo: rest of the available user settings!
      {'switch' => 'change-username', 'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'description' => 'Change user credentials to use a new username'},
      {'switch' => 'change-password', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'description' => 'Change user credentials to use a new password'},
      {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text'},
      {'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text'},
      {'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text'},
      {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text'},
      {'fieldName' => 'receiveNotifications', 'fieldLabel' => 'Receive Notifications', 'type' => 'checkbox'},
      {'fieldName' => 'linuxUsername', 'fieldLabel' => 'Linux Username', 'type' => 'text'},
      {'fieldName' => 'linuxPassword', 'fieldLabel' => 'Linux Password', 'type' => 'password'},
      {'fieldName' => 'linuxKeyPairId', 'fieldLabel' => 'Linux Key Pair ID', 'type' => 'password'},
      {'fieldName' => 'windowsUsername', 'fieldLabel' => 'Windows Username', 'type' => 'text'},
      {'fieldName' => 'windowsPassword', 'fieldLabel' => 'Windows Password', 'type' => 'password'},
      {'fieldName' => 'defaultGroup', 'fieldLabel' => 'Default Group ID', 'type' => 'text'},
      {'fieldName' => 'defaultCloud', 'fieldLabel' => 'Default Cloud ID', 'type' => 'text'},
      {'fieldName' => 'defaultPersona', 'fieldLabel' => 'Default Persona Name or Code or ID eg. standard, serviceCatalog or vdi', 'type' => 'text'},
      {'switch' => 'change-password', 'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'description' => 'Change user credentials to use a new password'},
      {'fieldName' => 'avatar', 'fieldLabel' => 'Avatar', 'type' => 'file', 'description' => 'Local filepath of image file to upload as user avatar'},
      {'fieldName' => 'desktopBackground', 'fieldLabel' => 'Desktop Background', 'type' => 'file', 'description' => 'Local filepath of image file to upload as user desktop background'},
      # api cannot yet modify isUsing2fa
      # {'switch' => '2fa', 'fieldName' => 'isUsing2fa', 'fieldLabel' => '2FA Enabled', 'type' => 'checkbox', 'description' => 'Enable or Disable 2FA for your user.'}
    ]
  end

end
