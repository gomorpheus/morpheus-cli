require 'fileutils'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'
require 'morpheus/logging'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get, :add, :update, :use, :unuse, :add_cloud, :remove_cloud, :remove, :current => :print_current
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :remote])
      opts.footer = "This outputs a paginated list of groups."
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
      print_h1 "Morpheus Groups"
      if groups.empty?
        puts yellow,"No groups currently configured.",reset
      else
        print_groups_table(groups)
        print_results_pagination(json_response)
        if @active_group_id
          active_group = groups.find { |it| it['id'] == @active_group_id }
          active_group = active_group || find_group_by_name_or_id(@active_group_id)
          #unless @appliances.keys.size == 1
            print cyan, "\n# => Currently using group #{active_group['name']}\n", reset
          #end
        else
          unless options[:remote]
            print "\n# => No active group, see `groups use`\n", reset
          end
        end
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
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :remote])
      opts.footer = "This outputs details about a specific group."
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
      is_active = @active_group_id && (@active_group_id == group['id'])
      print_h1 "Group Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'code',
        "Location" => 'location',
        "Clouds" => lambda {|it| it['zones'].collect {|z| z['name'] }.join(', ') },
        "Hosts" => 'serverCount'
      }
      print_description_list(description_cols, group)
      # puts "ID: #{group['id']}"
      # puts "Name: #{group['name']}"
      # puts "Code: #{group['code']}"
      # puts "Location: #{group['location']}"
      # puts "Clouds: #{group['zones'].collect {|it| it['name'] }.join(', ')}"
      # puts "Hosts: #{group['serverCount']}"
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
    use_it = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, add_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end
      opts.on( '--use', '--use', "Make this the current active group" ) do
        use_it = true
      end

      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Create a new group."
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
      if use_it
        ::Morpheus::Cli::Groups.set_active_group(@appliance_name, group['id'])
      end
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, update_group_option_types())
      # opts.on( '-l', '--location LOCATION', "Location" ) do |val|
      #   params[:location] = val
      # end
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update an existing group."
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

      #params = Morpheus::Cli::OptionTypes.prompt(update_group_option_types, options[:options], @api_client, {})
      params = options[:options] || {}

      if params.empty?
        puts optparse
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "CLOUD")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Add a cloud to a group."
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]", "CLOUD")
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Remove a cloud from a group."
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :auto_confirm, :remote])
      opts.footer = "Delete a group."
      # more info to display here
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
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.footer = "" +
        "This sets the active group.\n" +
        "The active group will be auto-selected for use during provisioning.\n" +
        "You can still use the --group option to override this."
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      # todo: this is a problem for unprivileged users, need to use find_group_by_id_for_provisioning(group_id)
      group = find_group_by_name_or_id(args[0])
      if !group
        print_red_alert "Group not found by name #{args[0]}"
        exit 1
      end

      if @active_group_id == group['id']
        print reset,"Already using the group #{group['name']}","\n",reset
      else
        ::Morpheus::Cli::Groups.set_active_group(@appliance_name, group['id'])
        # ::Morpheus::Cli::Groups.save_groups(@active_groups)
        #print cyan,"Switched active group to #{group['name']}","\n",reset
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end

  end

  def unuse(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      opts.footer = "" +
        "This will clear the current active group.\n" +
        "You will be prompted for a Group during provisioning."
      build_common_options(opts, options, [])
    end
    optparse.parse!(args)
    connect(options)

    if @active_group_id
      ::Morpheus::Cli::Groups.clear_active_group(@appliance_name)
      # unless options[:quiet]
      #   print cyan
      #   puts "Switched to no active group."
      #   puts "You will be prompted for Group during provisioning."
      #   print reset
      # end
      return true
    else
      puts "You are not using any group for appliance #{@appliance_name}"
      #return false
    end
  end

  def print_current(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [])
      opts.footer = "Prints the name of the current active group"
    end
    optparse.parse!(args)
    connect(options)

    group = @active_group_id ? find_group_by_name_or_id(@active_group_id) : nil
    if group
      print cyan,group['name'].to_s,"\n",reset
    else
      print yellow,"No active group. See `groups use`","\n",reset
      return false
    end
  end

  protected

  def print_groups_table(groups, opts={})
    table_color = opts[:color] || cyan
    active_group_id = @active_group_id # Morpheus::Cli::Groups.active_group
    rows = groups.collect do |group|
      is_active = @active_group_id && (@active_group_id == group['id'])
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

  # todo: This belongs elsewhere, like module Morpheus::Cli::ActiveGroups

public
  
  @@groups = nil

  class << self
    include Term::ANSIColor
    # Provides the current active group information
    def active_groups_map
      @@groups ||= load_group_file || {}
    end

    def active_groups
      active_groups_map
    end

    # Provides the current active group information (just the ID right now)
    def active_group(appliance_name=nil)
      if appliance_name == nil
        appliance_name, appliance_url = Morpheus::Cli::Remote.active_appliance
      end
      if !appliance_name
        return nil
      end
      return active_groups_map[appliance_name.to_sym]
    end

    # alias (unused)
    def active_group_id(appliance_name=nil)
      active_group(appliance_name)
    end

    def set_active_group(appliance_name, group_id)
      the_groups = active_groups_map
      the_groups[appliance_name.to_sym] = group_id
      save_groups(the_groups)
    end

    def clear_active_group(appliance_name)
      the_groups = active_groups_map
      the_groups.delete(appliance_name.to_sym)
      save_groups(the_groups)
    end

    def load_group_file
      fn = groups_file_path
      if File.exist? fn
        Morpheus::Logging::DarkPrinter.puts "loading groups file #{fn}" if Morpheus::Logging.debug?
        return YAML.load_file(fn)
      else
        {}
      end
    end

    def groups_file_path
      return File.join(Morpheus::Cli.home_directory, "groups")
    end

    def save_groups(groups_map)
      fn = groups_file_path
      if !Dir.exists?(File.dirname(fn))
        FileUtils.mkdir_p(File.dirname(fn))
      end
      File.open(fn, 'w') {|f| f.write groups_map.to_yaml } #Store
      FileUtils.chmod(0600, fn)
      @@groups = groups_map
    end

  end

end
