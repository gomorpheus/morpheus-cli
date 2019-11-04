require 'fileutils'
require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'
require 'morpheus/logging'

class Morpheus::Cli::Groups
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :get, :add, :update, :use, :unuse, :add_cloud, :remove_cloud, :remove, :current => :print_current
  alias_subcommand :details, :get
  register_subcommands :wiki, :update_wiki
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
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List groups (sites)."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.list(params)
        return 0
      end
      json_response = @groups_interface.list(params)
      render_result = render_with_format(json_response, options, 'groups')
      return 0 if render_result

      groups = json_response['groups']
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 "Morpheus Groups"
      if groups.empty?
        print yellow,"No groups currently configured.",reset,"\n"
      else
        print_groups_table(groups, options)
        print_results_pagination(json_response)
        if @active_group_id
          active_group = groups.find { |it| it['id'] == @active_group_id }
          active_group = active_group || find_group_by_name_or_id(@active_group_id)
          #unless @appliances.keys.size == 1
            print cyan, "\n# => Currently using group #{active_group['name']}\n", reset
          #end
        else
          unless options[:remote]
            print cyan, "\n# => No active group, see `groups use`\n", reset
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
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a group.\n" + 
                    "[name] is required. This is the name or id of a group. Supports 1-N arguments."
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

  def _get(arg, options={})
    begin
      if options[:dry_run]
        @groups_interface.setopts(options)
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @groups_interface.dry.get(arg.to_i)
        else
          print_dry_run @groups_interface.dry.list({name:arg})
        end
        return 0
      end
      group = find_group_by_name_or_id(arg)
      @groups_interface.setopts(options)
      #json_response = @groups_interface.get(group['id'])
      json_response = {'group' => group}
      
      render_result = render_with_format(json_response, options)
      return 0 if render_result

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
      @groups_interface.setopts(options)
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
      group_payload = {}

      #params = Morpheus::Cli::OptionTypes.prompt(update_group_option_types, options[:options], @api_client, {})
      params = options[:options] || {}

      if params.empty?
        puts optparse
        exit 1
      end

      group_payload.merge!(params)

      payload = {group: group_payload}
      @groups_interface.setopts(options)
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
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_zones(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_zones(group["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added cloud #{cloud["name"]} to group #{group['name']}"
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
      @groups_interface.setopts(options)
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
      @groups_interface.setopts(options)
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
      build_common_options(opts, options, [:quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      # todo: this is a problem for unprivileged users, need to use find_group_by_id_for_provisioning(group_id)
      group = find_group_by_name_or_id(args[0])
      if !group
        print_red_alert "Group not found by name #{args[0]}"
        return 1
      end
      if @active_group_id == group['id']
        unless options[:quiet]
          print reset,"Already using the group #{group['name']}","\n",reset
        end
      else
        ::Morpheus::Cli::Groups.set_active_group(@appliance_name, group['id'])
        # ::Morpheus::Cli::Groups.save_groups(@active_groups)
        unless options[:quiet]
          print cyan,"Switched active group to #{group['name']}","\n",reset
        end
        #list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
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
      opts.footer = "Print the name of the current active group"
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

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[group]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for an group." + "\n" +
                    "[group] is required. This is the name or id of an group."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?


      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.wiki(group["id"], params)
        return
      end
      json_response = @groups_interface.wiki(group["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Group Wiki Page: #{group['name']}"
        # print_h1 "Wiki Page Details"
        print cyan

        print_description_list({
          "Page ID" => 'id',
          "Name" => 'name',
          #"Category" => 'category',
          #"Ref Type" => 'refType',
          #"Ref ID" => 'refId',
          #"Owner" => lambda {|it| it['account'] ? it['account']['name'] : '' },
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
          "Updated By" => lambda {|it| it['updatedBy'] ? it['updatedBy']['username'] : '' }
        }, page)
        print reset,"\n"

        print_h2 "Page Content"
        print cyan, page['content'], reset, "\n"

      else
        print "\n"
        print cyan, "No wiki page found.", reset, "\n"
      end
      print reset,"\n"

      if open_wiki_link
        return view_wiki([args[0]])
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def view_wiki(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View group wiki page in a web browser" + "\n" +
                    "[group] is required. This is the name or id of an group."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/groups/#{group['id']}#!wiki"

      open_command = nil
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        open_command = "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        open_command = "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        open_command = "xdg-open #{link}"
      end

      if options[:dry_run]
        puts "system: #{open_command}"
        return 0
      end

      system(open_command)
      
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_wiki(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[group] [options]")
      build_option_type_options(opts, options, update_wiki_page_option_types)
      opts.on('--file FILE', "File containing the wiki content. This can be used instead of --content") do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          params['content'] = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        # use the filename as the name by default.
        if !params['name']
          params['name'] = File.basename(full_filename)
        end
      end
      opts.on(nil, '--clear', "Clear current page content") do |val|
        params['content'] = ""
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      group = find_group_by_name_or_id(args[0])
      return 1 if group.nil?
      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'page' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'page' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.prompt(update_wiki_page_option_types, options[:options], @api_client, options[:params])
        #params = passed_options
        params.deep_merge!(passed_options)

        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload.deep_merge!({'page' => params}) unless params.empty?
      end
      @groups_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @groups_interface.dry.update_wiki(group["id"], payload)
        return
      end
      json_response = @groups_interface.update_wiki(group["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for group #{group['name']}"
        wiki([group['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
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
        # name: is_active ? "#{green}#{group['name']}#{reset}#{table_color}" : group['name'],
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
      {:cloud_count => {:display_name => "CLOUDS"}},
      {:server_count => {:display_name => "HOSTS"}}
    ]
    print as_pretty_table(rows, columns, opts)
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
        #Morpheus::Logging::DarkPrinter.puts "loading groups file #{fn}" if Morpheus::Logging.debug?
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

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end
end
