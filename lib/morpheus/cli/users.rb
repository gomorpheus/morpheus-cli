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
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:account, :list, :query, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List users."
    end
    optparse.parse!(args)
    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      params = {}
      params.merge!(parse_list_options(options))
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.list(account_id, params)
        return
      end
      json_response = @users_interface.list(account_id, params)
      render_result = render_with_format(json_response, options, 'users')
      return 0 if render_result
      users = json_response['users']

      title = "Morpheus Users"
      subtitles = []
      if account
        subtitles << "Account: #{account['name']}".strip
      end
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if users.empty?
        print cyan,"No users found.",reset,"\n"
      else
        print_users_table(users, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:account, :query, :remote, :dry_run])
      opts.footer = "Get the number of users."
    end
    optparse.parse!(args)
    connect(options)
    begin
      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil
      params = {}
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username]")
      opts.on(nil,'--feature-access', "Display Feature Access") do |val|
        options[:include_features_access] = true
        params['includeAccess'] = true
      end
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
      build_common_options(opts, options, [:account, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a user." + "\n" +
                    "[username] is required. This is the username or id of a user."
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
      @users_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @users_interface.dry.get(account_id, args[0].to_i, params)
        else
          print_dry_run @users_interface.dry.get(account_id, {username: args[0]}, params)
        end
        return
      end

      if args[0].to_s =~ /\A\d{1,}\Z/
        user_id = args[0].to_i
      else
        user = find_user_by_username(account_id, args[0])

        if user.nil?
          print_red_alert "User #{args[0]} not found"
          exit 1
        end
        user_id = user['id']
      end

      user = @users_interface.get(account_id, user_id, params)['user']

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
      description_cols = {
          "ID" => 'id',
          "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          # "First" => 'firstName',
          # "Last" => 'lastName',
          # "Name" => 'displayName',
          "Name" => lambda {|it| it['firstName'] ? it['displayName'] : '' },
          "Username" => 'username',
          "Email" => 'email',
          "Notifications" => lambda {|it| it['receiveNotifications'].nil? ? '' : format_boolean(it['receiveNotifications']) },
          "Role" => lambda {|it| format_user_role_names(it) },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, user)

      # backward compatibility
      if user['access'].nil? && options[:include_features_access]
        user_feature_permissions_json = @users_interface.feature_permissions(account_id, user['id'])
        user_feature_permissions = user_feature_permissions_json['permissions'] || user_feature_permissions_json['featurePermissions']

        if user_feature_permissions
          print_h2 "Feature Permissions", options
          print cyan
          if user_feature_permissions.is_a?(Array)
            rows = user_feature_permissions.collect do |it|
              {name: it['name'], code: it['code'], access: get_access_string(it['access']) }
            end
            print as_pretty_table(rows, [:name, :code, :access], options)
          else
            rows = user_feature_permissions.collect do |code, access|
              {code: code, access: get_access_string(access) }
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

            print_h2 "#{label} Access", options
            print cyan

            if access.count > 0
              access.each {|it| it['access'] = get_access_string(it['access'])}

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
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username]")
      build_common_options(opts, options, [:account, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.on('-i', '--include-none-access', "Include Items with 'None' Access in Access List") do
        options[:display_none_access] = true
      end
      opts.footer = "Display Access for a user." + "\n" +
                    "[username] is required. This is the username or id of a user."
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
      user = find_user_by_username_or_id(account_id, args[0])
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
                {name: it['name'], code: it['code'], access: get_access_string(it['access']) }
              end
              print as_pretty_table(rows, [:name, :code, :access], options)
            else
              rows = user_feature_permissions.collect do |code, access|
                {code: code, access: get_access_string(access) }
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

            if access.count > 0
              access.each {|it| it['access'] = get_access_string(it['access'])}

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
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_option_type_options(opts, options, add_user_option_types)
      build_common_options(opts, options, [:account, :options, :payload, :json, :dry_run])
    end
    optparse.parse!(args)

    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
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
      details_options = [username]
      if account
        details_options.push "--account-id", account['id'].to_s
      end
      get(details_options)
    end
      

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username] [options]")
      build_option_type_options(opts, options, update_user_option_types)
      build_common_options(opts, options, [:account, :options, :payload, :json, :dry_run])
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

      user = find_user_by_username_or_id(account_id, args[0])
      return 1 if user.nil?

      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        #params = Morpheus::Cli::OptionTypes.prompt(update_user_option_types, options[:options], @api_client, options[:params])
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # if params.empty?
        #   print_red_alert "Specify at least one option to update"
        #   puts optparse
        #   return 1
        # end
        # prompt_option_types = update_user_option_types().reject {|it| 'role' == it['fieldName'] }
        # params = Morpheus::Cli::OptionTypes.prompt(prompt_option_types, params, @api_client)
        selected_roles = []
        selected_roles += params.delete('role').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['role']
        selected_roles += params.delete('roles').split(',').collect {|r| r.strip.empty? ? nil : r.strip}.uniq if params['roles']
        roles = prompt_user_roles(account_id, user['id'], selected_roles, options.merge(no_prompt: true))
        if !roles.empty?
          params['roles'] = roles.collect {|r| {id: r['id']} }
        end
        if params.empty?
          puts optparse.banner
          puts Morpheus::Cli::OptionTypes.display_option_types_help(update_user_option_types)
          return 1
        end

        
        payload = {'user' => params}
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
        username = payload['user']['username'] if payload['user'] && payload['user']['username']
        print_green_success "Updated user #{username}"
        details_options = [username]
        if account
          details_options.push "--account-id", account['id'].to_s
        end
        get(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def change_password(args)
    options = {}
    new_password = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username] [options]")
      opts.on('--password VALUE', String, "New password") do |val|
        new_password = val
      end
      build_common_options(opts, options, [:account, :options, :json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)

    if args.count < 1
      # print_error Morpheus::Terminal.angry_prompt
      # puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      puts optparse
      return 1
    end

    connect(options)
    begin

      account = find_account_from_options(options)
      account_id = account ? account['id'] : nil

      user = find_user_by_username_or_id(account_id, args[0])
      return 1 if user.nil?

      if !options[:quiet]
        print cyan, "Changing password for #{user['username']}", reset, "\n"
      end

      if new_password.nil?
        
        password_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'password', 'fieldLabel' => 'New Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
        new_password = password_prompt['password']

        confirm_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true}], options[:options], @api_client)
        confirm_password = confirm_prompt['passwordConfirmation']
        if confirm_password != new_password
          print_red_alert "Confirm password did not match."
          return 1
        end
      end

      if new_password.nil? || new_password.empty?
        print_red_alert "A new password is required"
        return 1
      end

      payload = {
        'user' => {
          'password' => new_password
        } 
      }
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.update(account_id, user['id'], payload)
        return
      end

      json_response = @users_interface.update(account_id, user['id'], payload)

      if options[:json]
        puts JSON.pretty_generate(json_response)
      elsif !options[:quiet]
        print_green_success "Updated password for user #{user['username']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[username]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run])
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

      user = find_user_by_username_or_id(account_id, args[0])
      return 1 if user.nil?
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the user #{user['username']}?")
        exit
      end
      @users_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @users_interface.dry.destroy(account_id, user['id'])
        return
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
      {'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => true, 'displayOrder' => 6},
      {'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => true, 'displayOrder' => 7},
      {'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'displayOrder' => 11, 'description' => "Role names (comma separated)"},
    ]
  end

  def update_user_option_types
    [
      {'fieldName' => 'firstName', 'fieldLabel' => 'First Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1},
      {'fieldName' => 'lastName', 'fieldLabel' => 'Last Name', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'username', 'fieldLabel' => 'Username', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'email', 'fieldLabel' => 'Email', 'type' => 'text', 'required' => false, 'displayOrder' => 4},
      {'fieldName' => 'password', 'fieldLabel' => 'Password', 'type' => 'password', 'required' => false, 'displayOrder' => 6},
      {'fieldName' => 'passwordConfirmation', 'fieldLabel' => 'Confirm Password', 'type' => 'password', 'required' => false, 'displayOrder' => 7},
      {'fieldName' => 'role', 'fieldLabel' => 'Role', 'type' => 'text', 'displayOrder' => 11, 'description' => "Role names (comma separated)"},
    ]
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
