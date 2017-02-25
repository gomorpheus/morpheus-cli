require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get, :add, :update, :use, :unuse, :add_cloud, :remove_cloud, :remove, :current => :print_current
  alias_subcommand :details, :get

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @active_groups = ::Morpheus::Cli::Groups.load_group_file
    @clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json])
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      json_response = @groups_interface.get(params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      groups = json_response['groups']
      print "\n" ,cyan, bold, "Morpheus Groups\n","==================", reset, "\n\n"
      if groups.empty?
        puts yellow,"No groups currently configured.",reset
      else
        print_groups_table(groups)
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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      #json_response = @groups_interface.get(group['id'])
      json_response = {'group' => group}
      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      group = json_response['group']

      active_group_id = @active_groups[@appliance_name.to_sym]
      is_active = active_group_id && (active_group_id == group['id'])

      print "\n" ,cyan, bold, "Group Details\n","==================", reset, "\n\n"
      print cyan
      puts "ID: #{group['id']}"
      puts "Name: #{group['name']}"
      puts "Code: #{group['code']}"
      puts "Location: #{group['location']}"
      puts "Clouds: #{group['zones'].collect {|it| it['name'] }.join(', ')}"
      puts "Hosts: #{group['serverCount']}"
      if is_active
        puts "\n => This is the active group."
      end

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
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-l', '--location LOCATION', "Location" ) do |val|
        params[:location] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    # if args.count < 1
    #   puts optparse
    #   exit 1
    # end
    connect(options)
    begin
      # group = {name: args[0], location: params[:location]}
      # payload = {group: group}
      group_payload = {}
      if args[0]
        group_payload[:name] = args[0]
        options[:options]['name'] = args[0] # to skip prompt
      end
      if params[:location]
        group_payload[:name] = params[:location]
        options[:options]['location'] = params[:location] # to skip prompt
      end
      all_option_types = add_group_option_types()
      params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {})
      group_payload.merge!(params)
      payload = {group: group_payload}

      if options[:dry_run]
        print_dry_run @groups_interface.dry.create(payload)
        return
      end
      json_response = @groups_interface.create(payload)
      group = json_response['group']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added group #{group['name']}"
        list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      opts.on( '-l', '--location LOCATION', "Location" ) do |val|
        params[:location] = val
      end
      build_common_options(opts, options, [:options, :json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      group_payload = {id: group['id']}

      all_option_types = update_group_option_types()
      #params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {})
      params = options[:options] || {}

      if params.empty?
        puts optparse.banner
        print_available_options(all_option_types)
        exit 1
      end

      group_payload.merge!(params)

      payload = {group: group_payload}

      if options[:dry_run]
        print_dry_run @groups_interface.dry.update(group['id'], payload)
        return
      end
      json_response = @groups_interface.update(group['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        #list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_cloud(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "CLOUD")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      cloud = find_cloud_by_name_or_id(args[1])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if found_zone
        print_red_alert "Cloud #{cloud['name']} is already in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones + [{'id' => cloud['id']}]
      payload = {group: {id: group["id"], zones: new_zones}}
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_zones(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_zones(group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added cloud #{cloud["id"]} to group #{group['name']}"
        #list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_cloud(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "CLOUD")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      cloud = find_cloud_by_name_or_id(args[1])
      current_zones = group['zones']
      found_zone = current_zones.find {|it| it["id"] == cloud["id"] }
      if !found_zone
        print_red_alert "Cloud #{cloud['name']} is not in group #{group['name']}."
        exit 1
      end
      new_zones = current_zones.reject {|it| it["id"] == cloud["id"] }
      payload = {group: {id: group["id"], zones: new_zones}}
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_zones(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_zones(group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed cloud #{cloud['name']} from group #{group['name']}"
        # list([])
        get([group["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :auto_confirm])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the group #{group['name']}?")
        exit
      end
      if options[:dry_run]
        print_dry_run @groups_interface.dry.destroy(group['id'])
        return
      end
      json_response = @groups_interface.destroy(group['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed group #{group['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def use(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "[--none]")
      opts.on('--none','--none', "Do not use an active group.") do |json|
        options[:unuse] = true
      end
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    connect(options)
    if options[:unuse]
      if @active_groups[@appliance_name.to_sym]
        @active_groups.delete(@appliance_name.to_sym)
      end
      ::Morpheus::Cli::Groups.save_groups(@active_groups)
      unless options[:quiet]
        print cyan
        puts "Switched to no active group."
        puts "You will be prompted for Group during provisioning."
        print reset
      end
      print reset
      return # exit 0
    end
    if args.length == 0
      active_group_id = @active_groups[@appliance_name.to_sym]
      if active_group_id
        active_group = find_group_by_id(active_group_id)
      end
      puts "#{optparse}"
      if active_group
        puts "\n=> You are currently using the group '#{active_group['name']}'\n"
      else
        puts "\nYou are not using any group.\n"
      end
      print reset
      exit 1
    end

    begin
      group = find_group_by_name_or_id(args[0])
      if !group
        print_red_alert "Group not found by name #{args[0]}"
        exit 1
      end

      if @active_groups[@appliance_name.to_sym] == group['id']
        print reset,"Already using the group #{group['name']}","\n",reset
      else
        @active_groups[@appliance_name.to_sym] = group['id']
        ::Morpheus::Cli::Groups.save_groups(@active_groups)
        #print cyan,"Switched to using group #{group['name']}","\n",reset
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def unuse(args)
    use(args + ['--none'])
  end

  def print_current(args)
    options = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    connect(options)

    #current_active_group = self.class.active_group
    active_group_id = @active_groups[@appliance_name.to_sym]
    group = active_group_id ? find_group_by_name_or_id(active_group_id) : nil
    if group
      print cyan,group['name'].to_s,"\n",reset
    else
      print dark,"No active group. See `remote use`","\n",reset
    end
  end

  # Provides the current active group information
  def self.active_group
    appliance_name, appliance_url = Morpheus::Cli::Remote.active_appliance
    if !defined?(@@groups)
      @@groups = load_group_file
    end
    return @@groups[appliance_name.to_sym]
  end


  def self.load_group_file
    remote_file = groups_file_path
    if File.exist? remote_file
      return YAML.load_file(remote_file)
    else
      {}
    end
  end

  def self.groups_file_path
    home_dir = Dir.home
    morpheus_dir = File.join(home_dir,".morpheus")
    if !Dir.exist?(morpheus_dir)
      Dir.mkdir(morpheus_dir)
    end
    return File.join(morpheus_dir,"groups")
  end

  def self.save_groups(group_map)
    File.open(groups_file_path, 'w') {|f| f.write group_map.to_yaml } #Store
  end

  protected

  def print_groups_table(groups, opts={})
    table_color = opts[:color] || cyan
    active_group_id = @active_groups[@appliance_name.to_sym]
    rows = groups.collect do |group|
      is_active = active_group_id && (active_group_id == group['id'])
      {
        active: (is_active ? "=>" : ""),
        id: group['id'],
        name: group['name'],
        location: group['location'],
        cloud_count: group['zones'] ? group['zones'].size : 0,
        server_count: group['serverCount']
      }
    end
    columns = [
      {:active => {:display_name => ""}},
      {:id => {:width => 10}},
      {:name => {:width => 16}},
      {:location => {:width => 32}},
      {:cloud_count => {:display_name => "Clouds"}},
      {:server_count => {:display_name => "Hosts"}}
    ]
    print table_color
    tp rows, columns
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

end
