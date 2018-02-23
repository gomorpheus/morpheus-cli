require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'

class Morpheus::Cli::UserGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper

  set_command_name :'user-groups'
  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :'add-user' => :add_user
  register_subcommands :'remove-user' => :remove_user
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @user_groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).user_groups
    @users_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).users
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction, :lastUpdated].each do |k|
        params[k] = options[k] unless options[k].nil?
      end

      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.list(nil, params)
        return
      end

      json_response = @user_groups_interface.list(nil, params)
      if options[:include_fields]
        json_response = {"userGroups" => filter_data(json_response["userGroups"], options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['userGroups'], options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      end
      user_groups = json_response['userGroups']
      title = "Morpheus User Groups"
      subtitles = []
      # if group
      #   subtitles << "Group: #{group['name']}".strip
      # end
      # if cloud
      #   subtitles << "Cloud: #{cloud['name']}".strip
      # end
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if user_groups.empty?
        print cyan,"No user groups found.",reset,"\n"
      else
        print_user_groups_table(user_groups, options)
        print_results_pagination(json_response, {:label => "user group", :n_label => "user groups"})
        # print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end
  
  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)

    begin
      user_group = find_user_group_by_name_or_id(nil, id)
      if user_group.nil?
        return 1
      end
      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.get(nil, user_group['id'])
        return
      end
      json_response = @user_groups_interface.get(nil, user_group['id'])
      user_group = json_response['userGroup']
      users = user_group['users'] || []
      if options[:include_fields]
        json_response = {"userGroup" => filter_data(json_response["userGroup"], options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['userGroup']], options)
        return 0
      end

      print_h1 "User Group Details"
      print cyan
      description_cols = {
        "ID" => lambda {|it| it['id'] },
        #"Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        "Server Group" => lambda {|it| it['serverGroup'] },
        "Sudo Access" => lambda {|it| format_boolean it['sudoAccess'] },
        # "Shared User" => lambda {|it| format_boolean it['sharedUser'] },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }
      print_description_list(description_cols, user_group)

      ## Users
      if users.size == 1
        print_h2 "User (1)"
      else
        print_h2 "Users (#{users.size})"
      end
      if users.size == 0
        print yellow,"No users",reset,"\n"
      else
        user_columns = [
          {"ID" => lambda {|user| user['id'] } },
          {"USERNAME" => lambda {|user| user['username'] } },
          {"NAME" => lambda {|user| user['displayName'] } },
        ]
        print as_pretty_table(users, user_columns)
      end

      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    user_ids = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--sudoUser [on|off]', String, "Sudo Access") do |val|
        params['sudoUser'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--serverGroup VALUE', String, "Server Group") do |val|
        params['name'] = val
      end
      opts.on('--users LIST', Array, "Users to include in this group, comma separated list of IDs or usernames") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          user_ids = []
        else
          user_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new user group." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
    end
    connect(options)
    begin
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        users = []
        if user_ids
          user_ids.each do |user_id|
            user = find_user_by_username_or_id(nil, user_id)
            return 1 if user.nil?
            users << user
          end
          params['users'] = users.collect {|it| it['id'] }
        end
        # todo: prompt?
        payload = {'userGroup' => params}
      end
      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.create(nil, payload)
        return
      end
      json_response = @user_groups_interface.create(nil, payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        user_group = json_response['userGroup']
        print_green_success "Added user group #{user_group['name']}"
        _get(user_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def update(args)
    options = {}
    params = {}
    user_ids = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name for this user group") do |val|
        params['name'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--sudoUser [on|off]', String, "Sudo Access. Default is off.") do |val|
        params['sudoUser'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--users LIST', Array, "Users to include in this group, comma separated list of IDs or usernames") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          user_ids = []
        else
          user_ids = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Update a user group." + "\n" +
                    "[name] is required. This is the name or id of a user group."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      user_group = find_user_group_by_name_or_id(nil, args[0])
      if user_group.nil?
        return 1
      end
      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # merge -O options into normally parsed options
        params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        if user_ids
          users = []
          user_ids.each do |user_id|
            user = find_user_by_username_or_id(nil, user_id)
            return 1 if user.nil?
            users << user
          end
          params['users'] = users.collect {|it| it['id'] }
        else
          # prevent server from clearing this!
          params['users'] = user_group['users'] #.collect {|it| it['id'] }
        end
        # todo: prompt?
        payload = {'userGroup' => params}
      end
      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.update(nil, user_group["id"], payload)
        return
      end
      json_response = @user_groups_interface.update(nil, user_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Updated user group #{user_group['name']}"
        _get(user_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_user(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [user]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
      opts.footer = "Add a user to a user group.\n" +
                    "[name] is required. This is the name or id of a user group.\n" +
                    "[user] is required. This is the username or id of a user. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      user_group = find_user_group_by_name_or_id(nil, args[0])
      if user_group.nil?
        return 1
      end
      

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        user_ids = args[1..-1]
        users = []
        user_ids.each do |user_id|
          user = find_user_by_username_or_id(nil, user_id)
          return 1 if user.nil?
          users << user
        end
        add_user_ids = users.collect {|it| it['id'] }
        current_users = (user_group['users'] || [])
        current_user_ids = current_users.collect {|it| it['id'] }
        new_user_ids = (current_user_ids + add_user_ids).uniq
        user_group_payload = {} # user_group
        user_group_payload['users'] = new_user_ids
        payload = {'userGroup' => user_group_payload}
      end
      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.update(nil, user_group["id"], payload)
        return 0
      end
      json_response = @user_groups_interface.update(nil, user_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if users.size == 1
            print_green_success  "Added #{users[0]['username']} to user group #{user_group['name']}"
          else
            print_green_success "Added #{users.size} users to user group #{user_group['name']}"
          end
        _get(user_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_user(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [user]")
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
      opts.footer = "Remove a user from a user group.\n" +
                    "[name] is required. This is the name or id of a user group.\n" +
                    "[user] is required. This is the username or id of a user. More than one can be passed."
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      return 1
    end
    connect(options)
    begin
      user_group = find_user_group_by_name_or_id(nil, args[0])
      if user_group.nil?
        return 1
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        user_ids = args[1..-1]
        users = []
        user_ids.each do |user_id|
          user = find_user_by_username_or_id(nil, user_id)
          return 1 if user.nil?
          users << user
        end
        remove_user_ids = users.collect {|it| it['id'] }
        current_users = (user_group['users'] || [])
        current_user_ids = current_users.collect {|it| it['id'] }
        new_user_ids = (current_user_ids - remove_user_ids).uniq
        user_group_payload = {} # user_group
        user_group_payload['users'] = new_user_ids
        payload = {'userGroup' => user_group_payload}
      end
      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.update(nil, user_group["id"], payload)
        return 0
      end
      json_response = @user_groups_interface.update(nil, user_group["id"], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if users.size == 1
            print_green_success  "Added #{users[0]['username']} to user group #{user_group['name']}"
          else
            print_green_success "Added #{users.size} users to user group #{user_group['name']}"
          end
        _get(user_group['id'], {})
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 127
    end
    connect(options)

    begin
      user_group = find_user_group_by_name_or_id(nil, args[0])
      if user_group.nil?
        return 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to delete user group '#{user_group['name']}'?", options)
        return false
      end

      # payload = {
      #   'userGroup' => {id: user_group["id"]}
      # }
      # payload['userGroup'].merge!(user_group)
      payload = params

      if options[:dry_run]
        print_dry_run @user_groups_interface.dry.destroy(nil, user_group["id"])
        return
      end

      json_response = @user_groups_interface.destroy(nil, user_group["id"])
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        print_green_success "Deleted user group #{user_group['name']}"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  private

  def print_user_groups_table(user_groups, opts={})
    columns = [
      {"ID" => lambda {|user_group| user_group['id'] } },
      {"NAME" => lambda {|user_group| user_group['name'] } },
      {"DESCRIPTION" => lambda {|user_group| user_group['description'] } },
      {"USERS" => lambda {|user_group| 
        users = user_group['users']
        if users
          n_users = 3
          if users.size > n_users
            users.first(n_users).collect { |user| user['username'] }.join(", ") + ", (#{users.size - n_users} more)"
          else
            users.collect { |user| user['username'] }.join(", ")
          end
        else
          ""
        end
      } },
      # {"KEY PAIR" => lambda {|user_group| 
      #   user_group['keyPair'] ? user_group['keyPair']['name'] : user_group['sharedKeyPairId']
      # } },
      # {"SUDO" => lambda {|user_group| format_boolean(user_group['sudoUser']) } },
    ]
    if opts[:include_fields]
      columns = opts[:include_fields]
    end
    print as_pretty_table(user_groups, columns, opts)
  end

  def find_user_group_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_user_group_by_id(account_id, val)
    else
      return find_user_group_by_name(account_id, val)
    end
  end

  def find_user_group_by_id(account_id, id)
    begin
      json_response = @user_groups_interface.get(account_id, id.to_i)
      return json_response['userGroup']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "User Group not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_user_group_by_name(account_id, name)
    user_groups = @user_groups_interface.list(account_id, {name: name.to_s})['userGroups']
    if user_groups.empty?
      print_red_alert "User Group not found by name #{name}"
      return nil
    elsif user_groups.size > 1
      print_red_alert "#{user_groups.size} user groups found by name #{name}"
      print_user_groups_table(user_groups, {color: red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return user_groups[0]
    end
  end

end
