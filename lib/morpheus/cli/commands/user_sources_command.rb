require 'morpheus/cli/cli_command'

class Morpheus::Cli::UserSourcesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'user-sources'
  set_command_description "View and manage user identity sources"

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :activate, :deactivate
  register_subcommands({:'update-subdomain' => :update_subdomain})
  register_subcommands({:'list-types' => :list_types})
  register_subcommands({:'get-type' => :get_type})

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @user_sources_interface = @api_client.user_sources
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
  end

  def handle(args)
    handle_subcommand(args)
  end


  def list(args)
    options = {}
    params = {}
    account = nil
    account_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '--tenant TENANT', String, "Filter by Tenant" ) do |val|
        account_id = val
      end
      opts.on( '-a', '--account ACCOUNT', "Filter by Tenant" ) do |val|
        account_id = val
      end
      opts.add_hidden_option('-a, --account') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_standard_list_options(opts, options)
      opts.footer = "List identity sources."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    if account_id
      account = find_account_by_name_or_id(account_id)
      if account.nil?
        return 1, "Tenant not found for '#{account_id}'"
      end
      account_id = account['id']
    end
    params.merge!(parse_list_options(options))
    @user_sources_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @user_sources_interface.dry.list(account_id, params)
      return 0, nil
    end
    json_response = @user_sources_interface.list(account_id, params)
    render_response(json_response, options, "userSources") do
      user_sources = json_response["userSources"]
      title = "Morpheus Identity Sources"
      subtitles = []
      if account
        subtitles << "Tenant: #{account['name']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if user_sources.empty?
        print cyan,"No identity sources found.",reset,"\n"
      else
        print_user_sources_table(user_sources, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
    
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      # opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
      #   options[:show_config] = true
      # end
      # opts.on('--no-config', "Do not display Config YAML." ) do
      #   options[:no_config] = true
      # end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about an identity source.
[name] is required. This is the name or id of an identity source.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(user_source_id, params, options)
    account_id = nil
    account = nil
    # account_id = args[0]
    # account = find_account_by_name_or_id(account_id)
    # exit 1 if account.nil?
    # account_id = account['id']
    # user_source_id = args[1]
    
    @user_sources_interface.setopts(options)
    if options[:dry_run]
      if user_source_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @user_sources_interface.dry.get(account_id, user_source_id.to_i)
      else
        print_dry_run @user_sources_interface.dry.list(account_id, {name:user_source_id})
      end
      return
    end
    user_source = find_user_source_by_name_or_id(account_id, user_source_id)
    if user_source.nil?
      return 1
    end
    # fetch by id to get config too
    json_response = nil
    if user_source_id.to_s =~ /\A\d{1,}\Z/
      json_response = {'userSource' => user_source}
    else
      json_response = @user_sources_interface.get(account_id, user_source['id'])
      user_source = json_response['userSource']
    end
      
    #user_source = json_response['userSource']
    render_response(json_response, options, "userSource") do
      print_h1 "Identity Source Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Type" => lambda {|it| it['type'] },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        #"Subdomain" => lambda {|it| it['subdomain'] },
        "Login URL" => lambda {|it| it['loginURL'] },
        "Default Role" => lambda {|it| it['defaultAccountRole'] ? it['defaultAccountRole']['authority'] : '' },
        "External Login" => lambda {|it| format_boolean it['externalLogin'] },
        "Allow Custom Mappings" => lambda {|it| format_boolean it['allowCustomMappings'] },
        "Active" => lambda {|it| format_boolean it['active'] },
      }
      print_description_list(description_cols, user_source)

      # show config settings...
      user_source_config = user_source['config']
      print_h2 "Configuration"
      if user_source_config
        columns = user_source_config.keys #.sort
        print_description_list(columns, user_source_config)
        # print reset,"\n"
      else
        print cyan,"No config found.","\n",reset
      end

      role_mappings = user_source['roleMappings']
      print_h2 "Role Mappings"
      if role_mappings && role_mappings.size > 0
        # print_h2 "Role Mappings"
        role_mapping_columns = [
          {"MORPHEUS ROLE" => lambda {|it| 
            it['mappedRole'] ? it['mappedRole']['authority'] : ''
          } },
          {"SOURCE ROLE NAME" => lambda {|it| it['sourceRoleName'] } },
          {"SOURCE ROLE FQN" => lambda {|it| it['sourceRoleFqn'] } },
        ]
        print as_pretty_table(role_mappings, role_mapping_columns)
      else
        print cyan,"No role mappings found for this identity source.","\n",reset
      end
      
      provider_settings = user_source['providerSettings']
      if provider_settings && !provider_settings.empty?
        print_h2 "Provider Settings"
        print_description_list({
          "Entity ID" => lambda {|it| it['entityId'] },
          "ACS URL" => lambda {|it| it['acsUrl'] }
        }, provider_settings)
        print_h2 "SP Metadata"
        print cyan
        print provider_settings['spMetadata']
        print "\n",reset
      else
        # print cyan,"No provider settings found.","\n",reset
      end
      print "\n",reset
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    account_id = nil
    type_code = nil
    role_mappings = nil
    role_mapping_names = nil
    default_role_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[account] [name]")
      opts.on( '--tenant TENANT', String, "Tenant Name or ID the identity source will belong to, default is your own." ) do |val|
        account_id = val
      end
      opts.on( '-a', '--account ACCOUNT', "Tenant Name or ID the identity source will belong to, default is your own." ) do |val|
        account_id = val
      end
      opts.add_hidden_option('-a, --account') if opts.is_a?(Morpheus::Cli::OptionParser)
      opts.on('--type CODE', String, "Identity Source Type") do |val|
        type_code = val
      end
      opts.on('--name VALUE', String, "Name for this identity source") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on("--allow-custom-mappings [on|off]", ['on','off'], "Allow Custom Mappings, Enable Role Mapping Permissions") do |val|
        params['allowCustomMappings'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--allowCustomMappings [on|off]", ['on','off'], "Allow Custom Mappings, Enable Role Mapping Permissions") do |val|
        params['allowCustomMappings'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.add_hidden_option('--allowCustomMappings')
      opts.on('--role-mappings MAPPINGS', String, "Role Mappings FQN in the format id1:FQN1,id2:FQN2") do |val|
        role_mappings = {}
        val.split(',').collect {|it| it.strip.split(':') }.each do |pair|
          k, v = pair[0], pair[1]
          if !k.to_s.empty?
            role_mappings[k.to_s] = v
          end
        end
      end
      opts.on('--role-mapping-names MAPPINGS', String, "Role Mapping Names in the format id1:Name1,id2:Name2") do |val|
        role_mapping_names = {}
        val.split(',').collect {|it| it.strip.split(':') }.each do |pair|
          k, v = pair[0], pair[1]
          if !k.to_s.empty?
            role_mapping_names[k.to_s] = v
          end
        end
      end
      
      opts.on('--default-role ID', String, "Default Role ID or Authority") do |val|
        default_role_id = val
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_standard_add_options(opts, options)
      opts.footer = "Create a new identity source." + "\n" +
                    "[account] is required. This is the name or id of an account."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args[0]
      account_id = args[0]
    end
    if args[1]
      params['name'] = args[1]
    end
    


      # # find the account first, or just prompt for that too please.
      # if !account_id
      #   print_error Morpheus::Terminal.angry_prompt
      #   puts_error  "missing required argument [account]\n#{optparse}"
      #   return 1
      # end

      # tenant is optional, it is expected in the url right now instead of in the payload...this sets both
      account = nil
      if account_id
        options[:options]['tenant'] = account_id
      end
      account_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'optionSource' => 'tenants', 'required' => false, 'description' => 'Tenant'}], options[:options], @api_client)
      if account_id
        options[:options].delete('tenant')
      end
      account_id = account_prompt['tenant']
      if !account_id.to_s.empty?
        # reload tenant by id, sure why not..
        account = find_account_by_name_or_id(account_id)
        return 1 if account.nil?
        account_id = account['id']
      else
        account_id = nil
      end
      

      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'userSource' => parse_passed_options(options)})

        # JD: should apply options on top of payload, but just do these two for now

        # Tenant
        if account
          payload['userSource']['account'] = {'id' => account['id'] }
        end

        # Name
        if params['name']
          payload['userSource']['name'] = params['name']
        end

      else
        payload.deep_merge!({'userSource' => parse_passed_options(options)})
        
        # support old -O options
        payload['userSource'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Tenant
        if account
          payload['userSource']['account'] = {'id' => account['id'] }
        end

        # Identity Source Type
        user_source_types = @user_sources_interface.list_types({userSelectable: true})['userSourceTypes']
        if user_source_types.empty?
          print_red_alert "No available Identity Source Types found"
          return 1
        end
        user_source_type = nil
        if !type_code
          user_source_type_dropdown = user_source_types.collect {|it| { 'name' => it['type'], 'value' => it['type']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'selectOptions' => user_source_type_dropdown, 'fieldLabel' => 'Type', 'required' => true}], options[:options])
          type_code = v_prompt['type'] if v_prompt['type']
        end
        user_source_type = user_source_types.find { |it| it['type'] == type_code }

        if user_source_type.nil?
          print_red_alert "Identity Source Type not found for '#{type_code}'"
          return 1
        end

        payload['userSource']['type'] = type_code

        # Name
        if params['name']
          payload['userSource']['name'] = params['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options])
          payload['userSource']['name'] = v_prompt['name'] if v_prompt['name']
        end
      
        # custom options by type
        my_option_types = load_user_source_type_option_types(user_source_type['type'])
        v_prompt = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options])
        payload['userSource'].deep_merge!(v_prompt)

        # Default Account Role
        # always prompt for role to lookup id from name
        if default_role_id
          options[:options]['defaultAccountRole'] = {'id' => default_role_id }
        end
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'defaultAccountRole', 'fieldName' => 'id', 'type' => 'select', 'selectOptions' => get_available_role_options(account_id), 'fieldLabel' => 'Default Role', 'required' => false }], options[:options])
        if v_prompt['defaultAccountRole'] && v_prompt['defaultAccountRole']['id']
          default_role_id = v_prompt['defaultAccountRole']['id']
        end
        payload['userSource']['defaultAccountRole'] = {'id' => default_role_id }

        # Allow Custom Mappings
        if !params['allowCustomMappings'].nil?
          payload['userSource']['allowCustomMappings'] = ["on","true"].include?(params['allowCustomMappings'].to_s)
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'allowCustomMappings', 'type' => 'checkbox', 'fieldLabel' => 'Allow Custom Mappings', 'defaultValue' => false}], options[:options])
          payload['userSource']['allowCustomMappings'] = ["on","true"].include?(v_prompt['allowCustomMappings'].to_s)
        end

        if role_mappings
          payload['roleMappings'] = role_mappings
        end

        if role_mapping_names
          payload['roleMappingNames'] = role_mapping_names
        end
        

      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.create(account_id, payload)
        return
      end
      # do it
      json_response = @user_sources_interface.create(account_id, payload)
      # print and return result
      render_response(json_response, options, 'userSource') do
        user_source = json_response['userSource']
        print_green_success "Added Identity Source #{user_source['name']}"
        _get(user_source['id'], {}, options)
      end
      return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    account_id = nil
    role_mappings = nil
    role_mapping_names = nil
    default_role_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--name VALUE', String, "Name for this identity source") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on("--allow-custom-mappings [on|off]", ['on','off'], "Allow Custom Mappings, Enable Role Mapping Permissions") do |val|
        params['allowCustomMappings'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on("--allowCustomMappings [on|off]", ['on','off'], "Allow Custom Mappings, Enable Role Mapping Permissions") do |val|
        params['allowCustomMappings'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.add_hidden_option('--allowCustomMappings')
      opts.on('--role-mappings MAPPINGS', String, "Role Mappings in the format id1:FQN,id2:FQN2") do |val|
        role_mappings = {}
        val.split(',').collect {|it| it.strip.split(':') }.each do |pair|
          k, v = pair[0], pair[1]
          if !k.to_s.empty?
            role_mappings[k.to_s] = v
          end
        end
      end
      opts.on('--role-mapping-names MAPPINGS', String, "Role Mapping Names in the format id1:Name1,id2:Name2") do |val|
        role_mapping_names = {}
        val.split(',').collect {|it| it.strip.split(':') }.each do |pair|
          k, v = pair[0], pair[1]
          if !k.to_s.empty?
            role_mapping_names[k.to_s] = v
          end
        end
      end
      opts.on('--default-role ROLE', String, "Default Role ID or Authority") do |val|
        default_role_id = val
      end
      build_standard_update_options(opts, options)
      opts.footer = "Update an identity source." + "\n" +
                    "[name] is required. This is the name or id of an identity source."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      user_source = find_user_source_by_name_or_id(nil, args[0])
      exit 1 if user_source.nil?
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'userSource' => parse_passed_options(options)})
      else
        payload.deep_merge!({'userSource' => parse_passed_options(options)})

        # Name
        if params['name']
          payload['userSource']['name'] = params['name']
        end
        
        # Description
        if params['description']
          payload['userSource']['description'] = params['description']
        end
        
        # Allow Custom Mappings
        if !params['allowCustomMappings'].nil?
          payload['userSource']['allowCustomMappings'] = params['allowCustomMappings']
        end

        if role_mappings
          payload['roleMappings'] = role_mappings
        end

        if role_mapping_names
          payload['roleMappingNames'] = role_mapping_names
        end

        # Default Account Role
        if default_role_id
          if default_role_id == 'null'
            payload['userSource']['defaultAccountRole'] = {'id' => nil }
          else
            # use no_prompt to convert name to id
            options[:options]['defaultAccountRole'] = {'id' => default_role_id }
            v_prompt = Morpheus::Cli::OptionTypes.no_prompt([{'fieldContext' => 'defaultAccountRole', 'fieldName' => 'id', 'type' => 'select', 'selectOptions' => get_available_role_options(user_source['account']['id']), 'fieldLabel' => 'Default Role', 'required' => false }], options[:options])
            if v_prompt['defaultAccountRole'] && v_prompt['defaultAccountRole']['id']
              default_role_id = v_prompt['defaultAccountRole']['id']
            end
            payload['userSource']['defaultAccountRole'] = {'id' => default_role_id }
          end
        end
      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.update(nil, user_source['id'], payload)
        return
      end
      json_response = @user_sources_interface.update(nil, user_source['id'], payload)
      render_response(json_response, options, 'userSource') do
        user_source = json_response['userSource'] || user_source
        print_green_success "Updated Identity Source #{user_source['name']}"
        _get(user_source['id'], {}, options)
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def activate(args)
    options = {}
    params = {}
    account_id = nil
    role_mappings = nil
    role_mapping_names = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Activate an identity source." + "\n" +
                    "[name] is required. This is the name or id of an identity source."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      user_source = find_user_source_by_name_or_id(nil, args[0])
      exit 1 if user_source.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {}
        # support old -O options
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.activate(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.activate(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Activated Identity Source #{user_source['name']}"
      get([user_source['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def deactivate(args)
    options = {}
    params = {}
    account_id = nil
    role_mappings = nil
    role_mapping_names = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Deactivate an identity source." + "\n" +
                    "[name] is required. This is the name or id of an identity source."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      user_source = find_user_source_by_name_or_id(nil, args[0])
      exit 1 if user_source.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {}
        # support old -O options
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.deactivate(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.deactivate(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Activated Identity Source #{user_source['name']}"
      get([user_source['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_subdomain(args)
    options = {}
    params = {}
    account_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--subdomain VALUE', String, "New subdomain for this identity source") do |val|
        params['subdomain'] = (val == 'null') ? nil : val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update subdomain for an identity source." + "\n" +
                    "[name] is required. This is the name or id of an identity source."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      user_source = find_user_source_by_name_or_id(nil, args[0])
      exit 1 if user_source.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {}
        payload['subdomain'] = params['subdomain'] if params.key?('subdomain')
        # support old -O options
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.update_subdomain(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.update_subdomain(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end
      # JD: uhh this updates the account too, it cannot be set per identity source ...yet
      print_green_success "Updated Identity Source #{user_source['name']} subdomain to '#{payload['subdomain']}'"
      get([user_source['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a user_source."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      user_source = find_user_source_by_name_or_id(nil, args[0])
      exit 1 if user_source.nil?

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the identity source #{user_source['name']}?", options)
        exit
      end
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.destroy(nil, user_source['id'])
        return
      end
      json_response = @user_sources_interface.destroy(nil, user_source['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed Identity Source #{user_source['name']}"
      #list([])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_types(args)
    options = {}
    params = {}
    account = nil
    account_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List identity source types."
    end
    optparse.parse!(args)
    connect(options)
    # instance is required right now.
    # account_id = args[0] if !account_id
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      # construct payload
      params.merge!(parse_list_options(options))
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.list_types(params)
        return
      end

      json_response = @user_sources_interface.list_types(params)
      if options[:json]
        puts as_json(json_response, options, "userSourceTypes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['userSourceTypes'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "userSourceTypes")
        return 0
      end
      user_source_types = json_response['userSourceTypes']
      title = "Morpheus Identity Source Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if user_source_types.empty?
        print cyan,"No types found.",reset,"\n"
      else
        print_user_source_types_table(user_source_types, options)
        print_results_pagination(json_response, {:label => "type", :n_label => "types"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_type(args)
    options = {}
    params = {}
    account = nil
    account_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about an identity source type." + "\n" +
                    "[type] is required. This is the type identifier."
    end
    optparse.parse!(args)
    connect(options)
    # instance is required right now.
    # account_id = args[0] if !account_id
    expected_arg_count = 1
    if args.count != expected_arg_count
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected #{expected_arg_count} and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      user_source_type_id = args[0]
      
      # construct payload
      @user_sources_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.list_types(user_source_type_id, params)
        return
      end
      json_response = @user_sources_interface.get_type(user_source_type_id, params)
      user_source_type = json_response["userSourceType"]
      if options[:json]
        puts as_json(json_response, options, "userSourceType")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "userSourceType")
        return 0
      elsif options[:csv]
        puts records_as_csv([user_source_type], options)
        return 0
      end
      title = "Identity Source Type"
      subtitles = []
      print_h1 title, subtitles
      print cyan
      description_cols = {
        #"ID" => lambda {|it| it['id'] },
        # "Name" => lambda {|it| it['name'] },
        # "Code" => lambda {|it| it['code'] },
        "Type" => lambda {|it| it['type'] },
        "External Login" => lambda {|it| format_boolean it['externalLogin'] },
        "Selectable" => lambda {|it| format_boolean it['userSelectable'] },
      }
      print_description_list(description_cols, user_source_type)

      # show config settings...
      my_option_types = user_source_type['optionTypes']
      
      
      if !my_option_types
        my_option_types = load_user_source_type_option_types(user_source_type['type'])
      end

      print_h2 "Configuration Option Types"
      if my_option_types && my_option_types.size > 0
        columns = [
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"FIELD NAME" => lambda {|it| [it['fieldContext'], it['fieldName']].select {|it| !it.to_s.empty? }.join('.') } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
        ]
        print as_pretty_table(my_option_types, columns)
      else
        print cyan,"No option types found.","\n",reset
      end

      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def find_user_source_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_user_source_by_id(account_id, val)
    else
      return find_user_source_by_name(account_id, val)
    end
  end

  def find_user_source_by_id(account_id, id)
    begin
      json_response = @user_sources_interface.get(account_id, id.to_i)
      return json_response['userSource']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Identity Source not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_source_by_name(account_id, name)
    user_sources = @user_sources_interface.list(account_id, {name: name.to_s})['userSources']
    if user_sources.empty?
      print_red_alert "Identity Source not found by name #{name}"
      return nil
    elsif user_sources.size > 1
      print_red_alert "#{user_sources.size} identity sources found by name #{name}"
      print_user_sources_table(user_sources, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return user_sources[0]
    end
  end

  def print_user_sources_table(user_sources, opts={})
    columns = [
      {"ID" => lambda {|user_source| user_source['id'] } },
      {"NAME" => lambda {|user_source| user_source['name'] } },
      {"TYPE" => lambda {|user_source| user_source['type'] } },
      {"TENANT" => lambda {|user_source| user_source['account'] ? user_source['account']['name'] : '' } },
      {"ACTIVE" => lambda {|user_source| format_boolean user_source['active'] } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(user_sources, columns, opts)
  end

  def print_user_source_types_table(user_sources, opts={})
    columns = [
      {"TYPE" => lambda {|user_source| user_source['type'] } },
      # {"NAME" => lambda {|user_source| user_source['name'] } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(user_sources, columns, opts)
  end

  # manual options until this is data driven
  # * ldap [ldap]
  # * jumpCloud [jumpCloud]
  # * activeDirectory [activeDirectory]
  # * okta [okta]
  # * oneLogin [oneLogin]
  # * saml [saml]
  # * customExternal [customExternal]
  # * customApi [customApi]
  def load_user_source_type_option_types(type_code)
    if type_code == 'ldap'
      [
        {'fieldContext' => 'config', 'fieldName' => 'url', 'type' => 'text', 'fieldLabel' => 'URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'bindingUsername', 'type' => 'text', 'fieldLabel' => 'Binding Username', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'bindingPassword', 'type' => 'password', 'fieldLabel' => 'Binding Password', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'requiredGroup', 'type' => 'text', 'fieldLabel' => 'Required group name (a.k.a. tag)', 'required' => true, 'description' => ''},
      ]
    elsif type_code == 'jumpCloud'
      [
        {'fieldContext' => 'config', 'fieldName' => 'organizationId', 'type' => 'text', 'fieldLabel' => 'Organization ID', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'bindingUsername', 'type' => 'text', 'fieldLabel' => 'Binding Username', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'bindingPassword', 'type' => 'password', 'fieldLabel' => 'Binding Password', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'requiredRole', 'type' => 'text', 'fieldLabel' => 'Required group name (a.k.a. tag)', 'required' => true, 'description' => ''},
      ]
    elsif type_code == 'activeDirectory'
      [
        {'fieldContext' => 'config', 'fieldName' => 'url', 'type' => 'text', 'fieldLabel' => 'AD Server', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'domain', 'type' => 'text', 'fieldLabel' => 'Domain', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'useSSL', 'type' => 'checkbox', 'fieldLabel' => 'Use SSL', 'required' => true, 'description' => '', 'defaultValue' => false},
        {'fieldContext' => 'config', 'fieldName' => 'bindingUsername', 'type' => 'text', 'fieldLabel' => 'Binding Username', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'bindingPassword', 'type' => 'password', 'fieldLabel' => 'Binding Password', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'requiredGroup', 'type' => 'text', 'fieldLabel' => 'Required Group', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'searchMemberGroups', 'type' => 'checkbox', 'fieldLabel' => 'Include Member Groups', 'required' => true, 'description' => '', 'defaultValue' => false},
      ]
    elsif type_code == 'okta'
      [
        {'fieldContext' => 'config', 'fieldName' => 'url', 'type' => 'text', 'fieldLabel' => 'OKTA URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'administratorAPIToken', 'type' => 'password', 'fieldLabel' => 'Adminstrator API Token', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'requiredGroup', 'type' => 'text', 'fieldLabel' => 'Required Group', 'required' => true, 'description' => ''}
      ]
    elsif type_code == 'oneLogin'
      [
        {'fieldContext' => 'config', 'fieldName' => 'subdomain', 'type' => 'text', 'fieldLabel' => 'OneLogin Subdomain', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'region', 'type' => 'text', 'fieldLabel' => 'OneLogin Region', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'clientSecret', 'type' => 'password', 'fieldLabel' => 'API Client Secret', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'clientId', 'type' => 'text', 'fieldLabel' => 'API Client ID', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'requiredRole', 'type' => 'text', 'fieldLabel' => 'Required Role', 'required' => true, 'description' => ''},
      ]
    elsif type_code == 'saml'
      [
        {'fieldContext' => 'config', 'fieldName' => 'url', 'type' => 'text', 'fieldLabel' => 'Login Redirect URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'doNotIncludeSAMLRequest', 'type' => 'checkbox', 'fieldLabel' => 'Exclude SAMLRequest Parameter', 'required' => true, 'description' => 'Do not include SAMLRequest parameter', 'defaultValue' => false},
        {'fieldContext' => 'config', 'fieldName' => 'logoutUrl', 'type' => 'text', 'fieldLabel' => 'Logout Post URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'publicKey', 'type' => 'textarea', 'fieldLabel' => 'Signing Public Key', 'required' => true, 'description' => ''},
      ]
    elsif type_code == 'customExternal'
      [
        {'fieldContext' => 'config', 'fieldName' => 'loginUrl', 'type' => 'text', 'fieldLabel' => 'External Login URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'doNotIncludeSAMLRequest', 'type' => 'checkbox', 'fieldLabel' => 'Exclude SAMLRequest Parameter', 'required' => true, 'description' => 'Do not include SAMLRequest parameter', 'defaultValue' => false},
        {'fieldContext' => 'config', 'fieldName' => 'logout', 'type' => 'text', 'fieldLabel' => 'External Logout URL', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'encryptionAlgo', 'type' => 'select', 'selectOptions' => ['NONE','AES','DES','DESede','HmacSHA1', 'HmacSHA256'].collect {|it| { 'name' => it, 'value' => it} }, 'fieldLabel' => 'Encryption Algorithm', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'encryptionKey', 'type' => 'text', 'fieldLabel' => 'Encryption Key', 'required' => true, 'description' => ''},
      ]
    elsif type_code == 'customApi'
      [
        {'fieldContext' => 'config', 'fieldName' => 'endpoint', 'type' => 'text', 'fieldLabel' => 'API Endpoint', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'apiStyle', 'type' => 'select', 'selectOptions' => ['Form URL Encoded [GET]','Form URL Encoded [POST]','JSON [POST]','XML [POST]','HTTP Basic [GET]'].collect {|it| { 'name' => it, 'value' => it} }, 'fieldLabel' => 'API Style', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'encryptionAlgo', 'type' => 'select', 'selectOptions' => ['NONE','AES','DES','DESede','HmacSHA1', 'HmacSHA256'].collect {|it| { 'name' => it, 'value' => it} }, 'fieldLabel' => 'Encryption Algorithm', 'required' => true, 'description' => ''},
        {'fieldContext' => 'config', 'fieldName' => 'encryptionKey', 'type' => 'text', 'fieldLabel' => 'Encryption Key', 'required' => true, 'description' => ''},
      ]
    else
      print "unknown identity source type: #{type_code}"
      []
    end
  end

  def get_available_role_options(account_id)
    available_roles = @account_users_interface.available_roles(account_id)['roles']
    # if available_roles.empty?
    #   print_red_alert "No available roles found."
    #   exit 1
    # end
    role_options = available_roles.collect {|role|
      {'name' => role['authority'], 'value' => role['id']}
    }
  end
end
