require 'fileutils'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/infrastructure_helper'
require 'morpheus/logging'

class Morpheus::Cli::AccountGroupsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::InfrastructureHelper


  register_subcommands :list, :get, :add, :update, :add_cloud, :remove_cloud, :remove

  # lives under image-builder domain right now
  set_command_hidden
  def command_name
    "tenants groups"
  end

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).account_groups
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts

    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List tenant groups."
    end
    optparse.parse!(args)
    if args.count == 1
      options[:account] = args[0]
    else
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      # load account
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      params.merge!(parse_list_options(options))
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.list(account['id'], params)
        return
      end
      json_response = @account_groups_interface.list(account['id'], params)
      if options[:json]
        puts as_json(json_response, options, "groups")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "groups")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["groups"], options)
        return 0
      end
      groups = json_response['groups']
      title = "Morpheus Groups - Tenant: #{account['name']}"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if groups.empty?
        print yellow,"No groups currently configured.",reset,"\n"
      else
        print_groups_table(groups, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [group]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a tenant group."
    end
    optparse.parse!(args)
    if args.count == 2
      options[:account] = args[0]
      options[:group] = args[1]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin

      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      if options[:dry_run]
        @account_groups_interface.setopts(options)
        if options[:group].to_s =~ /\A\d{1,}\Z/
          print_dry_run @account_groups_interface.dry.get(account_id, options[:group].to_i)
        else
          print_dry_run @account_groups_interface.dry.get(account_id, {name: options[:group]})
        end
        return
      end

      group = find_account_group_by_name_or_id(account_id, options[:group])
      @account_groups_interface.setopts(options)
      return 1 if group.nil?
      # skip redundant request
      # json_response = @account_groups_interface.dry.get(account_id, options[:group].to_i)
      json_response = {"group" => group}
      
      if options[:json]
        puts as_json(json_response, options, "group")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "group")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response["group"], options)
        return 0
      end

      print_h1 "Group Details", options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'code',
        "Location" => 'location',
        "Clouds" => lambda {|it| it['zones'].collect {|z| z['name'] }.join(', ') },
        "Hosts" => 'serverCount',
        "Tenant" => lambda {|it| account['name'] },
      }
      print_description_list(description_cols, group)
      # puts "ID: #{group['id']}"
      # puts "Name: #{group['name']}"
      # puts "Code: #{group['code']}"
      # puts "Location: #{group['location']}"
      # puts "Clouds: #{group['zones'].collect {|it| it['name'] }.join(', ')}"
      # puts "Hosts: #{group['serverCount']}"

      print reset,"\n"

      #puts instance
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [name]")
      build_option_type_options(opts, options, add_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end

      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Create a new tenant group."
    end
    optparse.parse!(args)
    if args.count == 1
      options[:account] = args[0]
    elsif args.count == 2
      options[:account] = args[0]
      options[:group] = args[1]
    else
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      group_payload = {}
      if options[:group]
        group_payload[:name] = options[:group]
        options[:options]['name'] = options[:group] # to skip prompt
      end
      if params[:location]
        group_payload[:name] = params[:location]
        options[:options]['location'] = params[:location] # to skip prompt
      end
      all_option_types = add_group_option_types()
      params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {})
      group_payload.merge!(params)
      payload = {group: group_payload}
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.create(account['id'], payload)
        return
      end
      json_response = @account_groups_interface.create(account['id'], payload)
      group = json_response['group']
      
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added group #{group['name']} to account #{account['name']}"
        list(["-A", account['id'].to_s])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [group] [options]")
      build_option_type_options(opts, options, update_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end
      build_common_options(opts, options, [:account, :options, :json, :dry_run, :remote])
      opts.footer = "Update an existing tenant group."
    end
    optparse.parse!(args)
    if args.count == 2
      options[:account] = args[0]
      options[:group] = args[1]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      group = find_account_group_by_name_or_id(account_id, options[:group])
      return 1 if group.nil?

      group_payload = {id: group['id']}

      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      if params.empty?
        puts optparse
        return 1
      end

      group_payload.merge!(params)

      payload = {group: group_payload}
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.update(account['id'], group['id'], payload)
        return
      end
      json_response = @account_groups_interface.update(account['id'], group['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        #list(["-A", account['id'].to_s])
        get([group["id"].to_s, "-A", account['id'].to_s])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_cloud(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [group] [cloud]")
      build_common_options(opts, options, [:account, :json, :dry_run, :remote])
      opts.footer = "Add a cloud to a tenant group."
    end
    optparse.parse!(args)
    if args.count == 3
      options[:account] = args[0]
      options[:group] = args[1]
      options[:cloud] = args[2]
    else
      raise_command_error "wrong number of arguments, expected 3 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      group = find_account_group_by_name_or_id(account_id, options[:group])
      return 1 if group.nil?

      # err, this is going to find public clouds only, not those in the subaccount
      # good enough for now?
      cloud = find_cloud_by_name_or_id(options[:cloud])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if found_zone
        print_red_alert "Cloud #{cloud['name']} is already in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones + [{'id' => cloud['id']}]
      payload = {group: {id: group["id"], zones: new_zones}}
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.update_zones(account['id'], group["id"], payload)
        return
      end
      json_response = @account_groups_interface.update_zones(account['id'], group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added cloud #{cloud["name"]} to group #{group['name']}"
        #list(["-A", account['id'].to_s])
        get([group["id"].to_s, "-A", account['id'].to_s])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_cloud(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [group] [cloud]")
      build_common_options(opts, options, [:account, :json, :dry_run, :remote])
      opts.footer = "Remove a cloud from a tenant group."
    end
    optparse.parse!(args)
    if args.count == 3
      options[:account] = args[0]
      options[:group] = args[1]
      options[:cloud] = args[2]
    else
      raise_command_error "wrong number of arguments, expected 3 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      group = find_account_group_by_name_or_id(account_id, options[:group])
      return 1 if group.nil?

      # err, this is going to find public clouds only, not those in the subaccount
      # good enough for now?
      cloud = find_cloud_by_name_or_id(options[:cloud])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if !found_zone
        print_red_alert "Cloud #{cloud['name']} is not in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones.reject {|it| it["id"] == cloud["id"] }
      payload = {group: {id: group["id"], zones: new_zones}}
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.update_zones(account['id'], group["id"], payload)
        return
      end
      json_response = @account_groups_interface.update_zones(account['id'], group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed cloud #{cloud['name']} from group #{group['name']}"
        # list(["-A", account['id'].to_s])
        get([group["id"].to_s, "-A", account['id'].to_s])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[tenant] [group]")
      build_common_options(opts, options, [:json, :dry_run, :auto_confirm, :remote])
      opts.footer = "Delete a tenant group."
    end
    optparse.parse!(args)
    if args.count == 2
      options[:account] = args[0]
      options[:group] = args[1]
    else
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      account = find_account_from_options(options)
      return 1 if account.nil?
      account_id = account['id']

      group = find_account_group_by_name_or_id(account_id, options[:group])
      return 1 if group.nil?
      
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the group #{group['name']}?")
        exit
      end
      @account_groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @account_groups_interface.dry.destroy(account['id'], group['id'])
        return
      end
      json_response = @account_groups_interface.destroy(account['id'], group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed group #{group['name']}"
        #list(["-A", account['id']])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  protected

  def print_groups_table(groups, options={})
    table_color = options[:color] || cyan
    rows = groups.collect do |group|
      {
        id: group['id'],
        name: group['name'],
        location: group['location'],
        cloud_count: group['zones'] ? group['zones'].size : 0,
        server_count: group['serverCount']
      }
    end
    columns = [
      {:id => {:width => 10}},
      {:name => {:width => 16}},
      {:location => {:width => 32}},
      {:cloud_count => {:display_name => "Clouds"}},
      {:server_count => {:display_name => "Hosts"}}
    ]
    print table_color
    puts as_pretty_table(rows, columns, options)
    print reset
  end

  def add_group_option_types()
    tmp_option_types = [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'location', 'fieldLabel' => 'Location', 'type' => 'text', 'required' => false, 'displayOrder' => 3}
    ]

    # Advanced Options
    # TODO: Service Registry

    return tmp_option_types
  end

  def update_group_option_types()
    add_group_option_types().collect {|it| it['required'] = false; it }
  end


  def find_account_group_by_name_or_id(account_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_account_group_by_id(account_id, val)
    else
      return find_account_group_by_name(account_id, val)
    end
  end

  def find_account_group_by_id(account_id, id)
    begin
      json_response = @account_groups_interface.get(account_id, id.to_i)
      return json_response['group']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Group not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_account_group_by_name(account_id, name)
    json_response = @account_groups_interface.list(account_id, {name: name.to_s})
    account_groups = json_response['groups']
    if account_groups.empty?
      print_red_alert "Group not found by name #{name}"
      return nil
    elsif account_groups.size > 1
      print_red_alert "#{account_groups.size} group found by name #{name}"
      rows = account_groups.collect { |it| {id: it['id'], name: it['name']} }
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      account_group = account_groups[0]
      return account_group
    end
  end


end
