require 'morpheus/cli/cli_command'

class Morpheus::Cli::UserSettingsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'user-settings'

  register_subcommands :get, :update, :'regenerate-access-token', :'clear-access-token'
  
  set_default_subcommand :get
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @user_settings_interface = @api_client.user_settings
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
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get your user settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.get(params)
        return
      end
      json_response = @user_settings_interface.get(params)
      if options[:json]
        puts as_json(json_response, options, "user")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "user")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['user']], options)
        return 0
      end

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
        "Notifications" => lambda {|it| format_boolean(it['receiveNotifications']) },
        "Linux Username" => lambda {|it| it['linuxUsername'] },
        "Linux Password" => lambda {|it| it['linuxPassword'] },
        "Linux Key Pair" => lambda {|it| it['linuxKeyPairId'] },
        "Windows Username" => lambda {|it| it['windowsUsername'] },
      }
      print_description_list(description_cols, user_settings)      

      if access_tokens && !access_tokens.empty?
        print_h2 "API Access Tokens"
        cols = {
          #"ID" => lambda {|it| it['id'] },
          "Client ID" => lambda {|it| it['clientId'] },
          "Username" => lambda {|it| it['username'] },
          "Expiration" => lambda {|it| format_local_dt(it['expiration']) }
        }
        print cyan
        puts as_pretty_table(access_tokens, cols)
      end
      
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def update(args)
    raw_args = args
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update your user settings."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    begin
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
  
      end

      if options[:options]
        payload['user'] ||= {}
        payload['user'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
      end

      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.update(params, payload)
        return
      end
      json_response = @user_settings_interface.update(params, payload)
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end

      print_green_success "Updated user settings"
      get([])
      return 0
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
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Regenerate API access token for a specific client.\n" +
                    "[client-id] is required. This is the id of an api client."
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
      payload = {}
      if options[:dry_run]
        print_dry_run @user_settings_interface.dry.regenerate_access_token(params, payload)
        return
      end
      json_response = @user_settings_interface.regenerate_access_token(params, payload)
      new_access_token = json_response['token']
      # update credentials if regenerating cli token
      if params['clientId'] == 'morph-cli'
        if new_access_token
          login_opts = {:remote_token => new_access_token}
          login_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).login(login_opts)
        end
      end
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      
      print_green_success "Regenerated #{params['clientId']} access token: #{new_access_token}"

      get([])
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client-id]")
      build_common_options(opts, options, [:payload, :options, :json, :dry_run, :quiet, :remote])
      opts.footer = "Clear API access token for a specific client.\n" +
                    "[client-id] is required. This is the id of an api client."
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
      payload = {}
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
      # if params['clientId'] == 'morph-cli'
      #   logout_result = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).logout
      # end
      print_green_success "Cleared #{params['clientId']} access token"
      if params['clientId'] == 'morph-cli'
        print yellow,"Your current access token is no longer valid, you will need to login again.",reset,"\n"
      end
      #get([])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

end
