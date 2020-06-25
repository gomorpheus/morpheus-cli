# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/option_types'
require 'morpheus/cli/mixins/accounts_helper'
require 'json'

class Morpheus::Cli::Users
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::WhoamiHelper
  register_subcommands :list, :count, :get, :add, :update, :remove, :permissions
  register_subcommands :'passwd' => :change_password
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @roles_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).roles
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      opts.on('--role AUTHORITY', String, "Role Name (authority)") do |val|
        params['role'] ||= []
        val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }.each do |v|
          params['role'] << v
        end
      end
      opts.on('--role-id ID', String, "Role ID") do |val|
        params['roleId'] ||= []
        val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }.each do |v|
          params['roleId'] << v
        end
      end
      build_standard_list_options(opts, options, [:account])
      opts.footer = "List users."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    options[:phrase] = args.join(" ") if args.count > 0
    connect(options)
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params['global'] = true if options[:global]
    params.merge!(parse_list_options(options))
    @users_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @users_interface.dry.list(account_id, params)
      return 0, nil
    end
    json_response = @users_interface.list(account_id, params)
    render_response(json_response, options, "users") do
      users = json_response['users']
      title = "Morpheus Users"
      subtitles = []
      if account
        subtitles << "Tenant: #{account['name']}".strip
      end
      if params['global'] && json_response['global']
        subtitles << "(All Tenants)"
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if users.empty?
        print cyan,"No users found.",reset,"\n"
      else
        print cyan
        print as_pretty_table(users, list_user_column_definitions, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def count(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      build_common_options(opts, options, [:account, :query, :remote, :dry_run])
      opts.footer = "Get the number of users."
    end
    optparse.parse!(args)
    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params['global'] = true if options[:global]
      params.merge!(parse_list_options(options))
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.list(account_id, params)
        return
      end
      json_response = @users_interface.list(account_id, params)
      # print number only
      if json_response['meta'] && json_response['meta']['total']
        print cyan, json_response['meta']['total'], reset, "\n"
      else
        print yellow, "unknown", reset, "\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[user]")
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      opts.on('-p','--permissions', "Display Permissions") do |val|
        options[:include_features_access] = true
        params['includeAccess'] = true
      end
      opts.on(nil,'--feature-access', "Display Permissions") do |val|
        options[:include_features_access] = true
        params['includeAccess'] = true
      end
      opts.add_hidden_option('--feature-access')
      opts.on(nil,'--group-access', "Display Group Access") do
        options[:include_sites_access] = true
        params['includeAccess'] = true
      end
      opts.on(nil,'--cloud-access', "Display Cloud Access") do
        options[:include_zones_access] = true
        params['includeAccess'] = true
      end
      opts.on(nil,'--instance-type-access', "Display Instance Type Access") do
        options[:include_instance_types_access] = true
        params['includeAccess'] = true
      end
      opts.on(nil,'--blueprint-access', "Display Blueprint Access") do
        options[:include_app_templates_access] = true
        params['includeAccess'] = true
      end
      opts.on(nil,'--all', "Display All Access Lists") do
        options[:include_features_access] = true
        options[:include_sites_access] = true
        options[:include_zones_access] = true
        options[:include_instance_types_access] = true
        options[:include_app_templates_access] = true
        params['includeAccess'] = true
      end
      opts.on('-i', '--include-none-access', "Include Items with 'None' Access in Access List") do
        options[:display_none_access] = true
      end
      build_standard_get_options(opts, options, [:account])
      opts.footer = <<-EOT
Get details about a user.
[user] is required. This is the username or id of a user. Supports 1-N arguments.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options={})
    args = [id] # heh
    params = {}
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params['global'] = true if options[:global]
    @users_interface.setopts(options)
    if options[:dry_run]
      if args[0].to_s =~ /\A\d{1,}\Z/
        print_dry_run @users_interface.dry.get(account_id, args[0].to_i, params)
      else
        print_dry_run @users_interface.dry.list(account_id, params.merge({username: args[0]}))
      end
      return
    end

    if args[0].to_s =~ /\A\d{1,}\Z/
      user_id = args[0].to_i
    else
      user = find_user_by_username(account_id, args[0], params)
      return 1 if user.nil?
      user_id = user['id']
    end
    # always get by id, index does not return 'access'
    json_response = @users_interface.get(account_id, user_id, params)
    user = json_response['user']

    if user.nil?
      print_red_alert "User #{args[0]} not found"
      exit 1
    end

    is_tenant_account = current_account['id'] != user['account']['id']

    json_response =  {'user' => user}

    if options[:json]
      puts as_json(json_response, options, "user")
      return 0
    elsif options[:yaml]
      puts as_yaml(json_response, options, "user")
      return 0
    elsif options[:csv]
      puts records_as_csv([user], options)
      return 0
    end

    print_h1 "User Details", options
    print cyan
    print_description_list(user_column_definitions, user)

    # backward compatibility
    if user['access'].nil? && options[:include_features_access]
      user_feature_permissions_json = @users_interface.feature_permissions(account_id, user['id'])
      user_feature_permissions = user_feature_permissions_json['permissions'] || user_feature_permissions_json['featurePermissions']

      if user_feature_permissions
        print_h2 "Feature Permissions", options
        print cyan
        if user_feature_permissions.is_a?(Array)
          rows = user_feature_permissions.collect do |it|
            {name: it['name'], code: it['code'], access: format_access_string(it['access']) }
          end
          print as_pretty_table(rows, [:name, :code, :access], options)
        else
          rows = user_feature_permissions.collect do |code, access|
            {code: code, access: format_access_string(access) }
          end
          print as_pretty_table(rows, [:code, :access], options)
        end
      else
        puts yellow,"No permissions found.",reset
      end
    else
      available_field_options = {'features' => 'Feature', 'sites' => 'Group', 'zones' => 'Cloud', 'instance_types' => 'Instance Type', 'app_templates' => 'Blueprint'}
      available_field_options.each do |field, label|
        if !(field == 'sites' && is_tenant_account) && options["include_#{field}_access".to_sym]
          access = user['access'][field.split('_').enum_for(:each_with_index).collect {|word, idx| idx == 0 ? word : word.capitalize}.join]
          access = access.reject {|it| it['access'] == 'none'} if !options[:display_none_access]

          if field == "features"
            # print_h2 "Permissions", options
            print_h2 "#{label} Access", options
          else
            print_h2 "#{label} Access", options
          end
          print cyan

          # access levels vary, default is none,read,user,full
          available_access_levels = ["none","read","user","full"]
          if field == 'sites' || field == 'zones' || field == 'instance_types' || field == 'app_templates'
            available_access_levels = ["none","read","full"]
          end
          if access.count > 0
            access.each {|it| it['access'] = format_access_string(it['access'], available_access_levels)}

            if ['features', 'instance_types'].include?(field)
              print as_pretty_table(access, [:name, :code, :access], options)
            else
              print as_pretty_table(access, [:name, :access], options)
            end
          else
            println yellow,"No #{label} Access Found.",reset
          end
        end
      end
    end
    print cyan
    print reset,"\n"
    return 0
  end

  def permissions(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[user]")
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      build_common_options(opts, options, [:account, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.on('-i', '--include-none-access', "Include Items with 'None' Access in Access List") do
        options[:display_none_access] = true
      end
      opts.footer = "Display Access for a user." + "\n" +
                    "[user] is required. This is the username or id of a user."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params['global'] = true if options[:global]
      user = find_user_by_username_or_id(account_id, args[0], params)
      return 1 if user.nil?
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.permissions(account_id, user['id'])
        return
      end

      is_tenant_account = current_account['id'] != user['account']['id']

      json_response = @users_interface.permissions(account_id, user['id'])

      # backward compatibility
      if !json_response['permissions'].nil?
        if options[:json]
          puts as_json(json_response, options, 'permissions')
          return 0
        elsif options[:yaml]
          puts as_yaml(json_response, options, 'permissions')
          return 0
        elsif options[:csv]
          puts records_as_csv(json_response['permissions'], options)
          return 0
        else
          user_feature_permissions = nil
          # permissions (Array) has replaced featurePermissions (map)
          user_feature_permissions = json_response['permissions'] || json_response['featurePermissions']
          print_h1 "User Permissions: #{user['username']}", options
          if user_feature_permissions
            print cyan
            if user_feature_permissions.is_a?(Array)
              rows = user_feature_permissions.collect do |it|
                {name: it['name'], code: it['code'], access: format_access_string(it['access']) }
              end
              print as_pretty_table(rows, [:name, :code, :access], options)
            else
              rows = user_feature_permissions.collect do |code, access|
                {code: code, access: format_access_string(access) }
              end
              print as_pretty_table(rows, [:code, :access], options)
            end

          else
            print yellow,"No permissions found.",reset,"\n"
          end
        end
      else
        if options[:json]
          puts as_json(json_response, options, 'access')
          return 0
        elsif options[:yaml]
          puts as_yaml(json_response, options, 'access')
          return 0
        elsif options[:csv]
          puts records_as_csv(json_response['access'], options)
          return 0
        end

        print_h1 "User Permissions: #{user['username']}", options

        available_field_options = {'features' => 'Feature', 'sites' => 'Group', 'zones' => 'Cloud', 'instance_types' => 'Instance Type', 'app_templates' => 'Blueprint'}
        available_field_options.each do |field, label|
          if !(field == 'sites' && is_tenant_account)
            access = json_response['access'][field.split('_').enum_for(:each_with_index).collect {|word, idx| idx == 0 ? word : word.capitalize}.join]
            access = access.reject {|it| it['access'] == 'none'} if !options[:display_none_access]

            print_h2 "#{label} Access", options
            print cyan
            available_access_levels = ["full","user","read","none"]
            if field == 'sites' || field == 'zones' || field == 'instance_types' || field == 'app_templates'
              available_access_levels = ["full","custom","none"]
            end
            if access.count > 0
              access.each {|it| it['access'] = format_access_string(it['access'], available_access_levels)}

              if ['features', 'instance_types'].include?(field)
                print as_pretty_table(access, [:name, :code, :access], options)
              else
                print as_pretty_table(access, [:name, :access], options)
              end
            else
              println cyan,"No #{label} Access Found.",reset
            end
          end
        end
      end
      print cyan
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username] [email] [first] [last] [options]")
      build_option_type_options(opts, options, add_user_option_types)
      build_common_options(opts, options, [:account, :options, :payload, :json, :dry_run])
      opts.footer = <<-EOT
Create a new user.
[user] is required. Username of the new user
[email] is required. Email address
[first] is optional. First Name
[last] is optional. Last Name
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:4)
    options[:options]['username'] = args[0] if args[0]
    options[:options]['email'] = args[1] if args[1]
    options[:options]['firstName'] = args[2] if args[2]
    options[:options]['lastName'] = args[3] if args[3]
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        # merge -O options into normally parsed options
        payload.deep_merge!(parse_passed_options(options))
        # remove role option_type, it is just for help display, the role prompt is separate down below
        prompt_option_types = add_user_option_types().reject {|it| 'role' == it['fieldName'] }
        v_prompt = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, options[:options], @api_client, options[:params])
        params.deep_merge!(v_prompt)

        # prompt for roles
        selected_roles = []
        selected_roles += params.delete('role').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['role']
        selected_roles += params.delete('roles').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['roles']
        roles = prompt_user_roles(account_id, nil, selected_roles, options)
        if !roles.empty?
          params['roles'] = roles.collect {|r| {id: r['id']} }
        end      
        payload = {'user' => params}
      end
      if options[:dry_run] && options[:json]
        puts as_json(payload, options)
        return 0
      end
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.create(account_id, payload)
        return
      end
      json_response = @users_interface.create(account_id, payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        username = "" # json_response['user']['username']
        username = payload['user']['username'] if payload['user'] && payload['user']['username']
        if account
          print_green_success "Added user #{username} to account #{account['name']}"
        else
          print_green_success "Added user #{username}"
        end
        # details_options = [username]
        # if account
        #   details_options.push "--account-id", account['id'].to_s
        # end
        # get(details_options + (options[:remote] ? ["-r",options[:remote]] : []))
        _get([payload['user']['id']], options)
      end
      

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[user] [options]")
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      build_option_type_options(opts, options, update_user_option_types)
      build_common_options(opts, options, [:account, :options, :payload, :json, :dry_run])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params['global'] = true if options[:global]
      user = find_user_by_username_or_id(account_id, args[0], params)
      return 1 if user.nil?

      # use --payload
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        # inject -O key=value options
        # payload.deep_merge!(parse_passed_options(options))
        params.deep_merge!(parse_passed_options(options))
        # user_prompt_output = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, payload['user'], @api_client)
        selected_roles = []
        selected_roles += params.delete('role').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['role']
        selected_roles += params.delete('roles').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['roles']
        roles = prompt_user_roles(account_id, user['id'], selected_roles, options.merge(no_prompt: true))
        # should it allow [] (no roles) ?
        if !roles.empty?
          params['roles'] = roles.collect {|r| {id: r['id']} }
        end
        payload.deep_merge!({'user' => params})
        if payload['user'].empty? # || options[:no_prompt]
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end
      end

      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.update(account_id, user['id'], payload)
        return
      end
      json_response = @users_interface.update(account_id, user['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        username = user['username'] # json_response['user']['username']
        if payload['user'] && payload['user']['username']
          username = payload['user']['username']
        end
        print_green_success "Updated user #{username}"
        # details_options = [username]
        # if account
        #   details_options.push "--account-id", account['id'].to_s
        # end
        # get(details_options + (options[:remote] ? ["-r",options[:remote]] : []))
        _get(user["id"], options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def change_password(args)
    params = {}
    options = {}
    new_password = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[user] [password] [options]")
      opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      # opts.on('--password VALUE', String, "New password") do |val|
      #   new_password = val
      # end
      build_standard_update_options(opts, options, [:account])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1,max:2) # [user] [password]
    connect(options)
    exit_code, err = 0, nil

    # user can be scoped to account (tenant)
    account = find_account_from_options(options)
    account_id = account ? account['id'] : nil
    params['global'] = true if options[:global]
    # fetch the user to update
    user = find_user_by_username_or_id(account_id, args[0], params)
    return 1 if user.nil?
    
    new_password = args[1] if args[1]

    # print a warning or important info
    if !options[:quiet]
      print cyan, "Changing password for #{user['username']}", reset, "\n"
    end
    # construct change_password payload
    
    # use --payload
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!(parse_passed_options(options))
    else
      # inject -O key=value options
      payload.deep_merge!(parse_passed_options(options))

      # prompt for password input
      current_input_attempt = 1
      still_prompting = new_password ? false : true
      while still_prompting do
        # New Password
        password_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'password', 'fieldLabel' => 'New Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
        new_password = password_prompt['password']
          
        # could validate password is "strong"
        # Confirm New Password
        confirm_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
        confirm_password = confirm_prompt['passwordConfirmation']
        if confirm_password != new_password
          print_red_alert "Confirm password did not match."
          new_password = nil
          unless ::Morpheus::Cli::OptionTypes::confirm("Would you like to try again?", options.merge({default: true}))
            return 9, "aborted login"
          end
        end
        still_prompting = !!new_password
      end
      payload = {
        'user' => {
          'password' => new_password
        } 
      }

    end
    @users_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @users_interface.dry.update(account_id, user['id'], payload)
      return
    end
    json_response = @users_interface.update(account_id, user['id'], payload)
    render_response(json_response, optparse, "user") do
      print_green_success "Updated password for user #{user['username']}"
    end
    return exit_code, err
  end

  def remove(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[user]")
        opts.on('-g','--global', "Global (All Tenants). Find users across all tenants. Default is your own tenant only.") do
        options[:global] = true
      end
      build_standard_remove_options(opts, options, [:account])
    end
    optparse.parse!(args)

    if args.count < 1
      puts optparse
      return 1
    end

    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params['global'] = true if options[:global]
      user = find_user_by_username_or_id(account_id, args[0], params)
      return 1 if user.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user #{user['username']}?")
        exit 9, "arborted"
      end
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.destroy(account_id, user['id'])
        return 0
      end
      json_response = @users_interface.destroy(account_id, user['id'])

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "User #{user['username']} removed"
        # list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private

  def add_user_option_types
    [
      {'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
      {'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => true, 'displayOrder' => 3},
      {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => true, 'displayOrder' => 4},
      {'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'displayOrder' => 5},
      {'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'displayOrder' => 6},
      {'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'description' => "Role names (comma separated)", 'displayOrder' => 7},
      {'fieldName' => 'receiveNotifications', 'fieldLabel' => 'Receive Notifications?', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true, 'displayOrder' => 58},
      {'fieldName' => 'linuxUsername', 'fieldLabel' => 'Linux Username', 'type' => 'text', 'required' => false, 'displayOrder' => 9},
      # {'fieldName' => 'linuxPassword', 'fieldLabel' => 'Linux Password', 'type' => 'password', 'required' => false, 'displayOrder' => 10},
      {'fieldName' => 'windowsUsername', 'fieldLabel' => 'Windows Username', 'type' => 'text', 'required' => false, 'displayOrder' => 11},
      # {'fieldName' => 'windowsPassword', 'fieldLabel' => 'Windows Password', 'type' => 'text', 'required' => false, 'displayOrder' => 12},
      #  'linuxUsername','windowsUsername','linuxKeyPairId'
    ]
  end

  def update_user_option_types
    add_user_option_types.collect {|it|
      it['required'] = false
      it
    }
  end

  # prompt user to select roles for a new or existing user
  # options['role'] can be passed as comma separated role names
  # if so, it will be used instead of prompting
  # returns array of role objects
  def prompt_user_roles(account_id, user_id, selected_roles=[], options={})
    passed_role_names = []
    if !selected_roles.empty?
      if selected_roles.is_a?(String)
        passed_role_names = selected_roles.split(',').uniq.compact.collect {|r| r.strip}
      else
        passed_role_names = selected_roles
      end
    end

    available_roles = @users_interface.available_roles(account_id, user_id)['roles']

    if available_roles.empty?
      print_red_alert "No available roles found."
      return 1
    end
    role_options = available_roles.collect {|role|
      {'name' => role['authority'], 'value' => role['id']}
    }

    roles = []

    if !passed_role_names.empty?
      invalid_role_names = []
      passed_role_names.each do |role_name|
        found_role = available_roles.find {|ar| ar['authority'] == role_name || ar['id'] == role_name.to_i}
        if found_role
          roles << found_role
        else
          invalid_role_names << role_name
        end
      end
      if !invalid_role_names.empty?
        print_red_alert "Invalid Roles: #{invalid_role_names.join(', ')}"
        exit 1
      end
    end

    if roles.empty?
      no_prompt = (options[:no_prompt] || (options[:options] && options[:options][:no_prompt]))
      if !no_prompt
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleId', 'fieldLabel' => 'Role', 'type' => 'select', 'selectOptions' => role_options, 'required' => true}], options[:options])
        role_id = v_prompt['roleId']
        roles << available_roles.find {|r| r['id'].to_i == role_id.to_i }
        add_another_role = true
        while add_another_role do
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'roleId', 'fieldLabel' => 'Another Role', 'type' => 'select', 'selectOptions' => role_options, 'required' => false}], options[:options])
          if v_prompt['roleId'].to_s.empty?
            add_another_role = false
          else
            role_id = v_prompt['roleId']
            roles << available_roles.find {|r| r['id'].to_i == role_id.to_i }
          end
        end
      end
    end

    roles = roles.compact
    return roles

  end

end
