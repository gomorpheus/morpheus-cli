require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::SubnetsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :subnets

  register_subcommands :list, :get, :add, :update, :remove
  # register_subcommands :'types' => :list_subnet_types
  register_subcommands :'types' => :list_subnet_types
  register_subcommands :'get-type' => :get_subnet_type

  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @networks_interface = @api_client.networks
    @network_types_interface = @api_client.network_types
    @subnets_interface = @api_client.subnets
    @subnet_types_interface = @api_client.subnet_types
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.on( '-c', '--cloud CLOUD', "Filter by Cloud" ) do |val|
        options[:cloud] = val
      end
      opts.on( '--network NETWORK', '--network NETWORK', "Filter by Network" ) do |val|
        options[:network] = val
      end
      opts.footer = "List subnets."
    end
    optparse.parse!(args)
    if args.count > 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    
    params.merge!(parse_list_options(options))
    network = nil
    if options[:network]
      network = find_network_by_name_or_id(options[:network])
      if network
        params['networkId'] = network['id']
      else
        return 1, "Network not found"
      end
    end
    cloud = nil
    if options[:cloud]
      cloud = find_cloud_by_name_or_id(options[:cloud])
      if cloud
        params['zoneId'] = cloud['id']
      else
        return 1, "Cloud not found"
      end
    end
    

    exit_code, err = 0, nil

    @subnets_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @subnets_interface.dry.list(params)
      return exit_code, err
    end
    json_response = @subnets_interface.list(params)
    subnets = json_response["subnets"]

    render_result = render_with_format(json_response, options, 'subnets')
    return exit_code, err if render_result

    title = "Morpheus Subnets"
    subtitles = []
    if network
      subtitles << "Network: #{network['name']}"
    end
    if cloud
      subtitles << "Cloud: #{cloud['name']}"
    end
    subtitles += parse_list_subtitles(options)
    print_h1 title, subtitles
    
    if subnets.empty?
      print cyan,"No subnets found.",reset,"\n"
    else
      subnet_columns = {
        "ID" => 'id',
        "Name" => 'name',
        #"Description" => 'description',
        "Network" => lambda {|it| it['network']['name'] rescue it['network'] },
        "Type" => lambda {|it| it['type']['name'] rescue it['type'] },
        "Cloud" => lambda {|it| it['zone']['name'] rescue it['zone'] },
        "CIDR" => lambda {|it| it['cidr'] },
        "DHCP" => lambda {|it| format_boolean(it['dhcpServer']) },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
      }
      print cyan
      print as_pretty_table(subnets, subnet_columns)
      print_results_pagination(json_response, {:label => "subnet", :n_label => "subnets"})
    end
    print reset,"\n"
    return exit_code, err  
    
  end


  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network] [subnet]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a subnet." + "\n" +
                    "[subnet] is required. This is the name or id of a subnet."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    exit_code, err = 0, nil
    begin
      subnet_id = nil
      if args[0].to_s =~ /\A\d{1,}\Z/
        subnet_id = args[0].to_i
      else
        subnet = find_subnet_by_name(args[0])
        return 1, "Security Group not found" if subnet.nil?
        subnet_id = subnet['id']
      end
      @subnets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnets_interface.dry.get(subnet_id)
        return exit_code, err
      end
      json_response = @subnets_interface.get(subnet_id)
      render_result = render_with_format(json_response, options, 'subnet')
      return exit_code, err if render_result

      subnet = json_response['subnet']
      if options[:json]
        puts as_json(json_response, options, "subnet")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "subnet")
        return 0
      elsif options[:csv]
        puts records_as_csv([subnet], options)
        return 0
      end
      print_h1 "Subnet Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
        "Network" => lambda {|it| subnet['network']['name'] rescue subnet['network'] },
        "Cloud" => lambda {|it| subnet['zone']['name'] rescue subnet['zone'] },
        "CIDR" => 'cidr',
        "Gateway" => 'gateway',
        "Netmask" => 'netmask',
        "Subnet" => 'subnetAddress',
        "Primary DNS" => 'dnsPrimary',
        "Secondary DNS" => 'dnsSecondary',
        "Pool" => lambda {|it| it['pool'] ? it['pool']['name'] : '' },
        "DHCP" => lambda {|it| format_boolean it['dhcpServer'] },
        #"Allow IP Override" => lambda {|it| it['allowStaticOverride'] ? 'Yes' : 'No' },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, subnet)

      if subnet['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if subnet['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if subnet['resourcePermission']['sites']
          subnet['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          {group: site['name'], default: site['default'] ? 'Yes' : ''}
        end
        columns = [:group, :default]
        print cyan
        print as_pretty_table(rows, columns)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    network_id = nil
    subnet_type_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] --network NETWORK")
      opts.on('--network NETWORK', String, "Network name or ID that this subnet will be a part of.") do |val|
        network_id = val
      end
      opts.on('-t', '--type ID', "Subnet Type Name or ID") do |val|
        subnet_type_id = val
      end
      opts.on('--name VALUE', String, "Name for this subnet") do |val|
        options[:options]['name'] = val
        # fill in silly names that vary by type
        options[:options].deep_merge!({'config' => {'subnetName' => val}})
      end
      opts.on('--cidr VALUE', String, "Name for this subnet") do |val|
        options[:options]['cidr'] = val
        # fill in silly names that vary by type
        options[:options].deep_merge!({'config' => {'subnetCidr' => val}})
      end
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a subnet") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a new subnet." + "\n" +
                    "--network is required. This is the name or id of a network." #+ "\n" +
                    #"[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    # if args.count < 1 || args.count > 2
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[1]
      options[:options]['name'] = args[1]
    end
    connect(options)
    begin
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'subnet' => passed_options}) unless passed_options.empty?
        
      else
        payload = {'subnet' => {}}
        payload.deep_merge!({'subnet' => passed_options}) unless passed_options.empty?
        
        # Network
        prompt_results = prompt_for_network(network_id, options)
        if prompt_results[:success]
          network = prompt_results[:network]
        else
          return 1, "Network prompt failed."
        end

        # Name
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this subnet.'}], options[:options])
        # payload['subnet']['name'] = v_prompt['name']

        # Subnet Type
        if !subnet_type_id
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Subnet Type', 'type' => 'select', 'optionSource' => 'subnetTypes', 'required' => true, 'description' => 'Choose a subnet type.'}], options[:options], @api_client, {networkId: network['id']})
          subnet_type_id = v_prompt['type']
        end
        subnet_type = find_subnet_type_by_name_or_id(subnet_type_id)
        return 1 if subnet_type.nil?
        if subnet_type['creatable'] == false
          raise_command_error "Subnet Type cannot be created: #{subnet_type['name']}"
        end
        payload['subnet']['type'] = {'id' => subnet_type['id'] }
        #payload['subnet']['type'] = {'code' => subnet_type['code'] }

        subnet_type_option_types = subnet_type['optionTypes']
        if subnet_type_option_types && subnet_type_option_types.size > 0
          # prompt for option types
          subnet_type_params = Morpheus::Cli::OptionTypes.prompt(subnet_type_option_types,options[:options],@api_client, {networkId: network['id']})
          payload['subnet'].deep_merge!(subnet_type_params)

        else
          # DEFAULT INPUTS

          # CIDR
          # if options['cidr']
          #   payload['subnet']['cidr'] = options['cidr']
          # else
          #   v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cidr', 'fieldLabel' => 'CIDR', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          #   payload['subnet']['cidr'] = v_prompt['cidr']
          # end

        end

        # Group Access
        # Group Access (default is All)
        if group_access_all.nil?
          if payload['resourcePermissions'].nil?
            payload['resourcePermissions'] ||= {}
            payload['resourcePermissions']['all'] = true
          end
        else
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['subnet']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['subnet']['visibility'] = options['visibility']
        end

      end

      @subnets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnets_interface.dry.create(network['id'], payload)
        return
      end
      json_response = @subnets_interface.create(network['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        subnet = json_response['subnet']
        print_green_success "Added subnet #{subnet['name']}"
        get_args = [network['id'], subnet['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        get(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end


  def update(args)
    options = {}
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[subnet]")
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--group-defaults LIST', Array, "Group Default Selection, comma separated list of group IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_defaults_list = []
        else
          group_defaults_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--accounts LIST', Array, "alias for --tenants") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a subnet") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a subnet." + "\n" +
                    "[subnet] is required. This is the name or id of a subnet."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network = find_network_by_name_or_id(args[0])
      return 1 if network.nil?

      subnet = find_subnet_by_name_or_id(network['id'], args[1])
      return 1 if subnet.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'subnet' => {
          }
        }
        
        # allow arbitrary -O options
        payload['subnet'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['subnet']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['subnet']['visibility'] = options['visibility']
        end

      end

      @subnets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnets_interface.dry.update(network['id'], subnet['id'], payload)
        return
      end
      json_response = @subnets_interface.update(network['id'], subnet['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        subnet = json_response['subnet']
        print_green_success "Updated subnet #{subnet['name']}"
        get_args = [network['id'], subnet['id']] + (options[:remote] ? ["-r",options[:remote]] : [])
        get(get_args)
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
      opts.banner = subcommand_usage("[subnet]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a subnet." + "\n" +
                    "[subnet] is required. This is the name or id of a subnet."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      subnet = find_subnet_by_name_or_id(args[0])
      return 1 if subnet.nil?

      subnet_type = find_subnet_type_by_name_or_id(subnet['type']['id'])
      return 1 if subnet_type.nil?
      if subnet_type['deletable'] == false
        raise_command_error "Subnet Type cannot be deleted: #{subnet_type['name']}"
      end

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the subnet: #{subnet['name']}?")
        return 9, "aborted command"
      end
      @subnets_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnets_interface.dry.destroy(subnet['id'])
        return 0
      end
      json_response = @subnets_interface.destroy(subnet['id'])
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Removed subnet #{subnet['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def get_subnet_type(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a subnet type.\n" +
                    "[type] is required. This is the id or name of a subnet type."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      @subnet_types_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @subnet_types_interface.dry.get(args[0].to_i)
        else
          print_dry_run @subnet_types_interface.dry.list({name:args[0]})
        end
        return
      end

      subnet_type = find_subnet_type_by_name_or_id(args[0])
      return 1 if subnet_type.nil?
      json_response = {'subnetType' => subnet_type}  # skip redundant request
      # json_response = @networks_interface.get(subnet_type['id'])
      
      render_result = render_with_format(json_response, options, 'subnetType')
      return 0 if render_result

      subnet_type = json_response['subnetType']

      title = "Morpheus Subnet Type"
      
      print_h1 "Morpheus Subnet Type", [], options
      
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Code" => 'name',
        "Description" => 'description',
        "Createable" => lambda {|it| format_boolean(it['creatable']) },
        "Deletable" => lambda {|it| format_boolean(it['deleteable']) },
      }
      print_description_list(description_cols, subnet_type)



      option_types = subnet_type['optionTypes'] || []
      option_types = option_types.sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }
      if !option_types.empty?
        print_h2 "Config Option Types", [], options
        option_type_cols = {
          "Name" => lambda {|it| it['fieldContext'].to_s != '' ? "#{it['fieldContext']}.#{it['fieldName']}" : it['fieldName'] },
          "Label" => lambda {|it| it['fieldLabel'] },
          "Type" => lambda {|it| it['type'] },
        }
        print cyan
        print as_pretty_table(option_types, option_type_cols)
      end
      
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_subnet_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List subnet types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:cloud]
        #return network_types_for_cloud(options[:cloud], options)
        zone = find_zone_by_name_or_id(nil, options[:cloud])
        #params["zoneTypeId"] = zone['zoneTypeId']
        params["zoneId"] = zone['id']
        params["creatable"] = true
      end
      @subnet_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @subnet_types_interface.dry.list(params)
        return
      end
      json_response = @subnet_types_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'subnetTypes')
      return 0 if render_result

      subnet_types = json_response['subnetTypes']

      title = "Morpheus Subnet Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if options[:cloud]
        subtitles << "Cloud: #{options[:cloud]}"
      end
      print_h1 title, subtitles
      if subnet_types.empty?
        print cyan,"No subnet types found.",reset,"\n"
      else
        rows = subnet_types.collect do |subnet_type|
          {
            id: subnet_type['id'],
            code: subnet_type['code'],
            name: subnet_type['name']
          }
        end
        columns = [:id, :name, :code]
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

end
