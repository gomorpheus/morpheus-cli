require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'

class Morpheus::Cli::UserSourcesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'user-sources'

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
    @user_sources_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).user_sources
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
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
      opts.on('--account ID', String, "Filter by Tenant") do |val|
        account_id = val
      end
      # opts.on('--technology VALUE', String, "Filter by technology") do |val|
      #   params['provisionType'] = val
      # end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List user sources."
    end
    optparse.parse!(args)
    connect(options)
    # instance is required right now.
    # account_id = args[0] if !account_id
    if args.count > 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    begin
      # construct payload
      if account_id
        account = find_account_by_name_or_id(account_id)
        return 1 if account.nil?
        account_id = account['id']
      end
      
      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.list(account_id, params)
        return
      end

      json_response = @user_sources_interface.list(account_id, params)
      if options[:json]
        puts as_json(json_response, options, "userSources")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['userSources'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "userSources")
        return 0
      end
      user_sources = json_response['userSources']
      title = "Morpheus User Sources"
      subtitles = []
      if account
        subtitles << "Account: #{account['name']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if user_sources.empty?
        if account
          print cyan,"No user sources found for account #{account['name']}.",reset,"\n"
        else
          print cyan,"No user sources found.",reset,"\n"
        end
      else
        print_user_sources_table(user_sources, options)
        print_results_pagination(json_response, {:label => "user source", :n_label => "user sources"})
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about an user source." + "\n" +
                    "[name] is required. This is the name or id of an user source."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    account_id = nil
    account = nil
    user_source_id = args[0]
    # account_id = args[0]
    # account = find_account_by_name_or_id(account_id)
    # exit 1 if account.nil?
    # account_id = account['id']
    # user_source_id = args[1]
    begin
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
      if options[:json]
        puts as_json(json_response, options, "userSource")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "userSource")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['userSource']], options)
        return 0
      end

      print_h1 "User Source Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Type" => lambda {|it| it['type'] },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        #"Subdomain" => lambda {|it| it['subdomain'] },
        "Login URL" => lambda {|it| it['loginURL'] },
        "Default Role" => lambda {|it| it['defaultAccountRole'] ? it['defaultAccountRole']['authority'] : '' },
        "Active" => lambda {|it| format_boolean it['active'] },
      }
      print_description_list(description_cols, user_source)

      # show config settings...
      user_source_config = user_source['config']
      print_h2 "#{user_source['type']} Configuration"
      if user_source_config
        columns = user_source_config.keys #.sort
        print_description_list(columns, user_source_config)
        # print reset,"\n"
      else
        print yellow,"No config found.","\n",reset
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
        print "\n",reset
      else
        print yellow,"No role mappings found for this user source.","\n",reset
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
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
      opts.on('--account ID', String, "Account this user source belongs to") do |val|
        account_id = val
      end
      opts.on('--type CODE', String, "User Source Type") do |val|
        type_code = val
      end
      opts.on('--name VALUE', String, "Name for this user source") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
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
      
      opts.on('--default-role ID', String, "Default Role ID") do |val|
        default_role_id = val
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a new user source." + "\n" +
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
    begin
      # find the account first, or just prompt for that too please.
      if !account_id
        print_error Morpheus::Terminal.angry_prompt
        puts_error  "missing required argument [account]\n#{optparse}"
        return 1
      end
      account = find_account_by_name_or_id(account_id)
      return 1 if account.nil?
      account_id = account['id']

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        payload = {'userSource' => {}}
        
        # User Source Type
        user_source_types = @user_sources_interface.list_types({userSelectable: true})['userSourceTypes']
        if user_source_types.empty?
          print_red_alert "No available User Source Types found"
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
          print_red_alert "User Source Type not found for '#{type_code}'"
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
        # todo: a proper select
        if !default_role_id
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'defaultAccountRole', 'fieldName' => 'id', 'type' => 'text', 'fieldLabel' => 'Default Account Role ID', 'required' => true}], options[:options])
          if v_prompt['defaultAccountRole'] && v_prompt['defaultAccountRole']['id']
            default_role_id = v_prompt['defaultAccountRole']['id']
          end
        end
        if default_role_id
          payload['userSource']['defaultAccountRole'] = {'id' => default_role_id }
        end


        if role_mappings
          payload['roleMappings'] = role_mappings
        end

        if role_mapping_names
          payload['roleMappingNames'] = role_mapping_names
        end

        # support old -O options
        payload['userSource'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        

      end
      # dry run?
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.create(account_id, payload)
        return
      end
      # do it
      json_response = @user_sources_interface.create(account_id, payload)
      # print and return result
      if options[:json]
        puts as_json(json_response, options)
        return 0
      end
      user_source = json_response['userSource']
      print_green_success "Added User Source #{user_source['name']}"
      get([user_source['id']])
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    account_id = nil
    role_mappings = nil
    role_mapping_names = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on('--name VALUE', String, "Name for this user source") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
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
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update a user source." + "\n" +
                    "[name] is required. This is the name or id of a user source."
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
        payload = {'userSource' => {}}

        # Name
        if params['name']
          payload['userSource']['name'] = params['name']
        end
        
        # Description
        if params['description']
          payload['userSource']['description'] = params['description']
        end
        
        if role_mappings
          payload['roleMappings'] = role_mappings
        end

        if role_mapping_names
          payload['roleMappingNames'] = role_mapping_names
        end

        # support old -O options
        payload['userSource'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      end

      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.update(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.update(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Updated User Source #{params['name'] || user_source['name']}"
      get([user_source['id']])
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
      opts.footer = "Activate a user source." + "\n" +
                    "[name] is required. This is the name or id of a user source."
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

      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.activate(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.activate(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Activated User Source #{user_source['name']}"
      get([user_source['id']])
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
      opts.footer = "Deactivate a user source." + "\n" +
                    "[name] is required. This is the name or id of a user source."
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

      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.deactivate(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.deactivate(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Activated User Source #{user_source['name']}"
      get([user_source['id']])
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
      opts.on('--subdomain VALUE', String, "New subdomain for this user source") do |val|
        params['subdomain'] = (val == 'null') ? nil : val
      end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update subdomain for a user source." + "\n" +
                    "[name] is required. This is the name or id of a user source."
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

      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.update_subdomain(nil, user_source['id'], payload)
        return
      end
      
      json_response = @user_sources_interface.update_subdomain(nil, user_source['id'], payload)
      
      if options[:json]
        puts JSON.pretty_generate(json_response)
        return
      end

      print_green_success "Activated User Source #{user_source['name']}"
      get([user_source['id']])
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

      unless Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user source #{user_source['name']}?", options)
        exit
      end
      if options[:dry_run]
        print_dry_run @user_sources_interface.dry.destroy(nil, user_source['id'])
        return
      end
      json_response = @user_sources_interface.destroy(nil, user_source['id'])

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end

      print_green_success "Removed User Source #{user_source['name']}"
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
      opts.footer = "List user source types."
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
      title = "Morpheus User Source Types"
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
      opts.footer = "Get details about a user source type." + "\n" +
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
      
      # all_user_source_types = @user_sources_interface.dry.list_types({})['userSourceTypes']
      # user_source_type = all_user_source_types.find {|it| it['type'] == user_source_type_id }
      # if !user_source_type
      #   print_red_alert "User Source Type not found by id '#{user_source_type_id}'"
      #   return 1
      # end

      # construct payload

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
      title = "User Source Type"
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
        print yellow,"No option types found.","\n",reset
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
        print_red_alert "User Source not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_source_by_name(account_id, name)
    user_sources = @user_sources_interface.list(account_id, {name: name.to_s})['userSources']
    if user_sources.empty?
      print_red_alert "User Source not found by name #{name}"
      return nil
    elsif user_sources.size > 1
      print_red_alert "#{user_sources.size} user sources found by name #{name}"
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
      {"ACCOUNT" => lambda {|user_source| user_source['account'] ? user_source['account']['name'] : '' } },
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
      print "unknown user source type: #{type_code}"
      []
    end
  end
end
