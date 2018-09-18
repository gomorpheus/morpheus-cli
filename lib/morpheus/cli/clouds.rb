# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'
require 'morpheus/cli/option_types'

class Morpheus::Cli::Clouds
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  register_subcommands :list, :count, :get, :add, :update, :remove, :firewall_disable, :firewall_enable, :security_groups, :apply_security_groups, :types => :list_cloud_types
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    # preload stuff
    get_available_cloud_types()
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options={}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name" ) do |group|
        options[:group] = group
      end
      opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
        options[:zone_type] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List clouds."
    end
    optparse.parse!(args)
    connect(options)
    begin
      if options[:zone_type]
        cloud_type = cloud_type_for_name(options[:zone_type])
        params[:type] = cloud_type['code']
      end
      if !options[:group].nil?
        group = find_group_by_name(options[:group])
        if !group.nil?
          params['groupId'] = group['id']
        end
      end

      params.merge!(parse_list_options(options))

      if options[:dry_run]
        print_dry_run @clouds_interface.dry.get(params)
        return
      end

      json_response = @clouds_interface.get(params)
      if options[:json]
        puts as_json(json_response, options, "zones")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "zones")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['zones'], options)
      else
        clouds = json_response['zones']
        title = "Morpheus Clouds"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud_type
          subtitles << "Type: #{cloud_type['name']}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles
        if clouds.empty?
          print cyan,"No clouds found.",reset,"\n"
        else
          print_clouds_table(clouds)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of clouds."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.get(params)
        return
      end
      json_response = @clouds_interface.get(params)
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
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a cloud.\n" +
                    "[name] is required. This is the name or id of a cloud."
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
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @clouds_interface.dry.get(arg.to_i)
        else
          print_dry_run @clouds_interface.dry.get({name:arg})
        end
        return
      end
      cloud = find_cloud_by_name_or_id(arg)
      #json_response = {'zone' => cloud}
      # if options[:dry_run]
      #   print_dry_run @clouds_interface.dry.get(cloud['id'])
      #   return
      # end
      json_response = @clouds_interface.get(cloud['id'])
      cloud = json_response['zone']
      cloud_stats = cloud['stats']
      # serverCounts moved to zone.stats.serverCounts
      server_counts = nil
      if cloud_stats
        server_counts = cloud_stats['serverCounts']
      else
        server_counts = json_response['serverCounts'] # legacy
      end
      if options[:json]
        puts as_json(json_response, options, 'zone')
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, 'zone')
        return 0
      end
      if options[:csv]
        puts records_as_csv([json_response['zone']], options)
        return 0
      end
      cloud_type = cloud_type_for_id(cloud['zoneTypeId'])
      print_h1 "Cloud Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| cloud_type ? cloud_type['name'] : '' },
        "Code" => 'code',
        "Location" => 'location',
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Groups" => lambda {|it| it['groups'].collect {|g| g.instance_of?(Hash) ? g['name'] : g.to_s }.join(', ') },
        "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        "Status" => lambda {|it| format_cloud_status(it) }
      }
      print_description_list(description_cols, cloud)
      
      print_h2 "Cloud Servers"
      print cyan
      if server_counts
        print "Container Hosts: #{server_counts['containerHost']}".center(20)
        print "Hypervisors: #{server_counts['hypervisor']}".center(20)
        print "Bare Metal: #{server_counts['baremetal']}".center(20)
        print "Virtual Machines: #{server_counts['vm']}".center(20)
        print "Unmanaged: #{server_counts['unmanaged']}".center(20)
        print "\n"
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
      opts.banner = subcommand_usage("[name] --group GROUP --type TYPE")
      opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
        params[:group] = val
      end
      opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
        params[:zone_type] = val
      end
      opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
        params[:description] = desc
      end
      opts.on( '--certificate-provider CODE', String, "Certificate Provider. Default is 'internal'" ) do |val|
        params[:certificate_provider] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    # if args.count < 1
    #   puts optparse
    #   exit 1
    # end
    connect(options)

    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['zone'] ||= {}
          payload['zone'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        cloud_payload = {name: args[0], description: params[:description]}
        # use active group by default
        params[:group] ||= @active_group_id

        # Group
        group_id = nil
        group = params[:group] ? find_group_by_name_or_id(params[:group]) : nil
        if group
          group_id = group["id"]
        else
          # print_red_alert "Group not found or specified!"
          # exit 1
          groups_dropdown = @groups_interface.get({})['groups'].collect {|it| {'name' => it["name"], 'value' => it["id"]} }
          group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => groups_dropdown, 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
          group_id = group_prompt['group']
        end
        cloud_payload['groupId'] = group_id
        # todo: pass groups as an array instead

        # Cloud Name

        if args[0]
          cloud_payload[:name] = args[0]
          options[:options]['name'] = args[0] # to skip prompt
        elsif !options[:no_prompt]
          # name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true}], options[:options])
          # cloud_payload[:name] = name_prompt['name']
        end

        # Cloud Type

        cloud_type = nil
        if params[:zone_type]
          cloud_type = cloud_type_for_name(params[:zone_type])
        elsif !options[:no_prompt]
          # print_red_alert "Cloud Type not found or specified!"
          # exit 1
          cloud_types_dropdown = cloud_types_for_dropdown
          cloud_type_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => 'Cloud Type', 'selectOptions' => cloud_types_dropdown, 'required' => true, 'description' => 'Select Cloud Type.'}],options[:options],@api_client,{})
          cloud_type_code = cloud_type_prompt['type']
          cloud_type = cloud_type_for_name(cloud_type_code) # this does work
        end
        if !cloud_type
          print_red_alert "A cloud type is required."
          exit 1
        end
        cloud_payload[:zoneType] = {code: cloud_type['code']}

        cloud_payload['config'] ||= {}
        if params[:certificate_provider]
          cloud_payload['config']['certificateProvider'] = params[:certificate_provider]
        else
          cloud_payload['config']['certificateProvider'] = 'internal'
        end

        all_option_types = add_cloud_option_types(cloud_type)
        params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {zoneTypeId: cloud_type['id']})
        # some optionTypes have fieldContext='zone', so move those to the root level of the zone payload
        if params['zone'].is_a?(Hash)
          cloud_payload.deep_merge!(params.delete('zone'))
        end
        cloud_payload.deep_merge!(params)
        payload = {zone: cloud_payload}
      end
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.create(payload)
        return
      end
      json_response = @clouds_interface.create(payload)
      cloud = json_response['zone']
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        #list([])
        get([cloud["id"]])
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
      # opts.on( '-g', '--group GROUP', "Group Name" ) do |val|
      #   params[:group] = val
      # end
      # opts.on( '-t', '--type TYPE', "Cloud Type" ) do |val|
      #   params[:zone_type] = val
      # end
      # opts.on( '-d', '--description DESCRIPTION', "Description (optional)" ) do |desc|
      #   params[:description] = desc
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      return 1 if cloud.nil?
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['zone'] ||= {}
          payload['zone'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        cloud_type = cloud_type_for_id(cloud['zoneTypeId'])
        cloud_payload = {id: cloud['id']}
        all_option_types = update_cloud_option_types(cloud_type)
        #params = Morpheus::Cli::OptionTypes.prompt(all_option_types, options[:options], @api_client, {zoneTypeId: cloud_type['id']})
        params = options[:options] || {}
        if params.empty?
          puts_error optparse.banner
          puts_error format_available_options(all_option_types)
          exit 1
        end
        # some optionTypes have fieldContext='zone', so move those to the root level of the zone payload
        if params['zone'].is_a?(Hash)
          cloud_payload.merge!(params.delete('zone'))
        end
        cloud_payload.merge!(params)
        payload = {zone: cloud_payload}
      end

      if options[:dry_run]
        print_dry_run @clouds_interface.dry.update(cloud['id'], payload)
        return
      end
      json_response = @clouds_interface.update(cloud['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        #list([])
        get([cloud["id"]])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      opts.on( '-f', '--force', "Force Remove" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the cloud #{cloud['name']}?")
        exit
      end
      json_response = @clouds_interface.destroy(cloud['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed cloud #{cloud['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.firewall_disable(cloud['id'])
        return
      end
      json_response = @clouds_interface.firewall_disable(cloud['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.firewall_enable(cloud['id'])
        return
      end
      json_response = @clouds_interface.firewall_enable(cloud['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      zone_id = cloud['id']
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.security_groups(zone_id)
        return
      end
      json_response = @clouds_interface.security_groups(zone_id)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Cloud: #{cloud['name']}"
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    clear_or_secgroups_specified = false
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage("[name] [-s] [--clear]")
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        options[:securityGroupIds] = []
        clear_or_secgroups_specified = true
      end
      opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        options[:securityGroupIds] = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      cloud = find_cloud_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.apply_security_groups(cloud['id'])
        return
      end
      json_response = @clouds_interface.apply_security_groups(cloud['id'], options)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_cloud_types(args)
    options={}
    params = {}
    optparse = OptionParser.new do|opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      if options[:dry_run]
        print_dry_run @clouds_interface.dry.cloud_types({})
        return
      end
      cloud_types = get_available_cloud_types() # @clouds_interface.dry.cloud_types({})['zoneTypes']
      if options[:json]
        print JSON.pretty_generate({zoneTypes: cloud_types})
        print "\n"
      else
        print_h1 "Morpheus Cloud Types"
        if cloud_types.empty?
          print yellow,"No instances found.",reset,"\n"
        else
          print cyan
          cloud_types = cloud_types.select {|it| it['enabled'] }
          rows = cloud_types.collect do |cloud_type|
            {id: cloud_type['id'], name: cloud_type['name'], code: cloud_type['code']}
          end
          tp rows, :id, :name, :code
        end
        print reset,"\n"
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def print_clouds_table(clouds, opts={})
    table_color = opts[:color] || cyan
    rows = clouds.collect do |cloud|
      status = nil
      if cloud['status'] == 'ok'
        status = "#{green}OK#{table_color}"
      elsif cloud['status'].nil?
        status = "#{white}UNKNOWN#{table_color}"
      else
        status = "#{red}#{cloud['status'] ? cloud['status'].upcase : 'N/A'}#{cloud['statusMessage'] ? "#{table_color} - #{cloud['statusMessage']}" : ''}#{table_color}"
      end
      cloud_type = cloud_type_for_id(cloud['zoneTypeId'])
      {
        id: cloud['id'],
        name: cloud['name'],
        type: cloud_type ? cloud_type['name'] : '',
        location: cloud['location'],
        groups: (cloud['groups'] || []).collect {|it| it.instance_of?(Hash) ? it['name'] : it.to_s }.join(', '),
        servers: cloud['serverCount'],
        status: status
      }
    end
    columns = [
      :id, :name, :type, :location, :groups, :servers, :status
    ]
    print table_color
    tp rows, columns
    print reset

  end

  def add_cloud_option_types(cloud_type)
    # note: Type is selected before this
    tmp_option_types = [
      #{'fieldName' => 'zoneType.code', 'fieldLabel' => 'Image Type', 'type' => 'select', 'selectOptions' => cloud_types_for_dropdown, 'required' => true, 'description' => 'Cloud Type.', 'displayOrder' => 0},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'code', 'fieldLabel' => 'Code', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'location', 'fieldLabel' => 'Location', 'type' => 'text', 'required' => false, 'displayOrder' => 3},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private', 'displayOrder' => 4},
    ]

    # TODO: Account

    # Details (zoneType.optionTypes)

    if cloud_type && cloud_type['optionTypes']
      # adjust displayOrder to put these at the end
      #tmp_option_types = tmp_option_types + cloud_type['optionTypes']
      cloud_type['optionTypes'].each do |opt|
        tmp_option_types << opt.merge({'displayOrder' => opt['displayOrder'].to_i + 100})
      end
    end

    # TODO:
    # Advanced Options
    ## (a whole bunch needed here)

    # Provisioning Options

    ## PROXY (dropdown)
    ## BYPASS PROXY FOR APPLIANCE URL (checkbox)
    ## USER DATA LINUX (code)

    return tmp_option_types
  end

  def update_cloud_option_types(cloud_type)
    add_cloud_option_types(cloud_type).collect {|it| it['required'] = false; it }
  end

  def cloud_types_for_dropdown
    get_available_cloud_types().select {|it| it['enabled'] }.collect {|it| {'name' => it['name'], 'value' => it['code']} }
  end

  def format_cloud_status(cloud, return_color=cyan)
    out = ""
    status_string = cloud['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{cloud['statusMessage'] ? "#{return_color} - #{cloud['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

end
