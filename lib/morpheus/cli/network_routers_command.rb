require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkRoutersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-routers'
  register_subcommands :list, :get, :firewall, :dhcp, :routes, :types, :type, :add, :update, :remove
  register_subcommands :add_firewall_rule, :remove_firewall_rule
  register_subcommands :add_route, :remove_route
  register_subcommands :update_permissions

  def initialize()
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_routers_interface = @api_client.network_routers
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
    @accounts_interface = @api_client.accounts
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network routers."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.list(params)
        return
      end
      json_response = @network_routers_interface.list(params)
      routers = json_response["networkRouters"]
      if options[:json]
        puts as_json(json_response, options, "networkRouters")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkRouters")
        return 0
      elsif options[:csv]
        puts records_as_csv(routers, options)
        return 0
      end
      title = "Morpheus Network Routers"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if routers.empty?
        print cyan,"No network routers found.",reset,"\n"
      else
        # STATUS	NAME	ROUTER TYPE	SERVICE	NETWORKS	EXTERNAL IP
        rows = routers.collect {|router|
          row = {
            id: router['id'],
            name: router['name'],
            status: format_router_status(router),
            router_type: (router['type'] || {})['name'],
            group: router['site'] ? router['site']['name'] : 'Shared',
            service: (router['networkServer'] || {})['name'],
            networks: (router['externalNetwork'] || {})['name'],
            external_ip: router['externalIp']
          }
          row
        }
        columns = [:id, :name, :status, :router_type, :group, :service, :networks, :external_ip]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        if json_response['meta']
          print_results_pagination(json_response, {:label => "network routers", :n_label => "network routers"})
        else
          print_results_pagination({'meta'=>{'total'=>rows.size,'size'=>rows.size,'max'=>options[:max] || rows.size,'offset'=>0}}, {:label => "network routers", :n_label => "network routers"})
        end
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router]")
      opts.on('--details', "Display details: firewall, DHCP, and routing." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display network router details." + "\n" +
          "[router] is required. This is the name or id of a network router."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
  end

  def _get(id, options)
    begin
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_routers_interface.dry.get(arg.to_i)
        else
          print_dry_run @network_routers_interface.dry.list({name:arg})
        end
        return
      end
      router = find_router(id)
      if router.nil?
        return 1
      end

      json_response = {'networkRouter' => router}

      if options[:json]
        puts as_json(json_response, options, "networkRouter")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkRouter")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['networkRouter']], options)
        return 0
      end

      print_h1 "Network Router Details"
      print cyan
      description_cols = {
          "ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Status" => lambda {|it| format_router_status(it)},
          "Type" => lambda {|it| it['type']['name']},
          "Service" => lambda {|it| it['networkServer'] ? it['networkServer']['name'] : nil},
          "Group" => lambda {|it| it['site'] ? it['site']['name'] : 'Shared'},
          # "Integration" => lambda {|it| router_integration_label(it)},
          "Provider ID" => lambda {|it| it['providerId'] || it['externalId']},
          "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
      }

      print_description_list(description_cols, router)

      if (router['interfaces'] || []).count > 0
        rows = router['interfaces'].sort_by{|it| it['networkPosition']}.collect do |it|
          {
              position: it['networkPosition'],
              name: it['name'],
              type: it['interfaceType'],
              network: (it['network'] || {})['name'],
              link: it['externalLink'],
              ip_address: it['ipAddress'],
              subnet: it['cidr'],
              enabled: format_boolean(it['enabled'])
          }
        end
        print_h2 "Interfaces"
        puts as_pretty_table(rows, [:position, :name, :type, :link, :network, :ip_address, :subnet, :enabled])
      end

      if router['type']['hasFirewall']
        print_h2 "Firewall"
        print cyan
        print_firewall(router, options[:details])
      end
      if router['type']['hasDhcp']
        print_h2 "DHCP"
        print cyan
        print_dhcp(router, options[:details])
      end
      if router['type']['hasRouting'] && options[:details]
        print_h2 "Routes"
        print cyan
        print_routes(router)
      end
      if router['permissions'] && options[:details]
        print_h2 "Tenant Permissions"
        print cyan
        description_cols = {
            "Visibility" => lambda{|it| (it['permissions']['visibility'] || '').capitalize},
            "Tenants" => lambda{|it|
              accounts = (it['permissions']['tenantPermissions'] || {})['accounts'] || []
              accounts.count > 0 ? accounts.join(', ') : ''
            }
        }
        print_description_list(description_cols, router)
        println
      end
      print reset
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[type] [name] [options]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on('-t', '--type VALUE', String, "Name or ID of router type") do |val|
        options[:options]['routerType'] = val
      end
      opts.on('-n', '--name VALUE', String, "Name for this network router") do |val|
        options[:options]['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        options[:options]['description'] = val
      end
      opts.on('-s', '--server VALUE', String, "Network server") do |val|
        options[:network_server] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to enable / disable the network router. Default is on") do |val|
        options[:enabled] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network router."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args.count > 0
      options[:options]['routerType'] = args[0]
    end
    if args.count > 1
      params['name'] = args[1]
    end
    begin
      if options[:payload]
        payload = options[:payload]
      else
        router_type = prompt_router_type(options)
        router = {'type' => {'id' => router_type['id']}, 'enabled' => options[:enabled].nil? || options[:enabled] }

        group_options = available_groups

        if options[:group]
          group = avail_groups.find {|it| it['name'] == options[:group] || "#{it['value']}" == "#{options[:group]}".downcase}

          if group.nil?
            print_red_alert "Group #{options[:group]} not found"
            exit 1
          end
          router['site'] = {'id' => group['value']}
        else
          default_group = group_options.find {|it| it['value'] == 'shared'} ? 'shared' : nil
          group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'required' => true, 'selectOptions' => group_options, 'defaultValue' => default_group}], options[:options], @api_client, params, nil, true)['group']
          router['site'] = {'id' => group_id}
        end

        # add router type to be used for option prompts
        params = {'router' => {'site' => router['site']}, 'routerType' => {'id' => router_type['id']}}

        if router_type['hasNetworkServer']
          if options[:server]
            server = find_network_server(options[:server])
            if server.nil?
              print_red_alert "Network server #{options[:server]} not found"
              exit 1
            end
          else
            server_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'required' => true, 'optionSource' => 'networkServer'}], options[:options], @api_client, params, nil, true)['networkServer']
            server = {'id' => server_id}
          end
          router['networkServer'] = {'id' => server['id']}
          params['networkServerId'] = server['id']
        else
          # prompt cloud
          if options[:cloud]
            cloud = find_cloud_by_name_or_id(options[:cloud])
            if cloud.nil?
              print_red_alert "Cloud #{options[:cloud]} not found"
              exit 1
            end
          else
            cloud_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zone', 'type' => 'select', 'fieldLabel' => 'Cloud', 'required' => true, 'optionSource' => 'routerTypeCloud'}], options[:options], @api_client, params, nil, true)['zone']
            cloud = {'id' => cloud_id}
          end
          router['zone'] = params['zone'] = {'id' => cloud['id']}
        end

        # prompt for enabled
        router['enabled'] = options[:enabled].nil? ? Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'description' => 'Enable Router.', 'defaultValue' => true, 'required' => false}], options, @api_client, {})['enabled'] == 'on' : options[:enabled]

        option_types = router_type['optionTypes'].reject {|it| ['enabled'].include?(it['fieldName'])}.sort {|it| it['displayOrder']}

        # prompt options
        option_opts = options[:options].deep_merge!({'config' => options[:options].clone})
        option_result = Morpheus::Cli::OptionTypes.prompt(option_types, option_opts.merge({:context_map => {'networkRouter' => ''}}), @api_client, params)
        payload = {'networkRouter' => router.deep_merge(option_result)}
        payload['networkRouter']['config'] = option_result['config'] if option_result['config']
      end

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.create(payload)
        return
      end

      json_response = @network_routers_interface.create(payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "Added Network Router #{payload['networkRouter']['name']}"
      _get(json_response['id'], options)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[router]")
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network router."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    begin
      router = find_router(args[0])
      if router.nil?
        return 1
      end

      payload = parse_payload(options)

      if payload.nil?
        if !options[:enabled].nil?
          params['enabled'] = options[:enabled]
        end

        if options[:options]
          params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) || ['name', 'routerType'].include?(k)})
        end
        payload = {'networkRouter' => params}
      end

      if payload['networkRouter'].empty?
        print_green_success "Nothing to update"
        return
      end

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.update(router['id'], payload)
        return
      end

      json_response = @network_routers_interface.update(router['id'], payload)

      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if json_response['success']
          print_green_success  "Network router updated"
          _get(router['id'], options)
        else
          print_red_alert "Error updating network router: #{json_response['msg'] || json_response['errors']}"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network router.\n" +
          "[router] is required. This is the name or id of an existing network router."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      router = find_router(args[0])

      return if !router

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network router '#{router['name']}'?", options)
        return 9, "aborted command"
      end
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.destroy(router['id'], query_params)
        return
      end
      json_response = @network_routers_interface.destroy(router['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Network router #{router['name']} is being removed..."
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display network router firewall details." + "\n" +
          "[router] is required. This is the name or id of a network router."
    end

    optparse.parse!(args)
    connect(options)

    if args.count < 1
      puts optparse
      return 1
    end
    _firewall(args[0], options)
  end

  def _firewall(router_id, options)
    begin
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_routers_interface.dry.get(router_id.to_i)
        else
          print_dry_run @network_routers_interface.dry.list({name:router_id})
        end
        return
      end
      router = find_router(router_id)
      if router.nil?
        return 1
      end

      json_response = {'networkRouter' => router}

      if options[:json]
        puts as_json(json_response, options, "networkRouter")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkRouter")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['networkRouter']], options)
        return 0
      end

      if !options[:rules_only]
        print_h1 "Network Router Firewall Details for: #{router['name']}"
      end

      print cyan

      if router['type']['hasFirewall']
        print_firewall(router, true, options[:rules_only])
      else
        print_red_alert "Firewall not supported for #{router['type']['name']}"
      end
      println reset
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add_firewall_rule(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[router] [name]")
      opts.on('-n', '--name VALUE', String, "Name for this firewall rule") do |val|
        params['name'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network router firewall rule."
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args.count > 1
      params['name'] = args[1]
    end
    begin
      router = find_router(args[0])

      if router.nil?
        return 1
      end

      if !router['type']['hasFirewall']
        print_red_alert "Firewall not supported for #{router['type']['name']}"
        return 1
      end

      if options[:payload]
        payload = options[:payload]
      else
        params['name'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Rule Name', 'required' => true}], options[:options], @api_client, params)['name']

        option_types = router['type']['ruleOptionTypes'].reject {|it| ['name'].include?(it['fieldName'])}.sort {|it| it['displayOrder']}

        # prompt options
        api_params = {}
        api_params['networkServerId'] = router['networkServer']['id'] if router['networkServer']
        api_params['zoneId'] = router['zone']['id'] if router['networkServer'].nil?
        option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'networkRouter' => ''}}), @api_client, api_params, nil, true)
        payload = {'rule' => params.deep_merge(option_result)}
      end

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.create_firewall_rule(router['id'], payload)
        return
      end

      json_response = @network_routers_interface.create_firewall_rule(router['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "\nAdded Network Router Firewall Rule #{payload['rule']['name']}\n"
      _firewall(router['id'], options.merge({:rules_only => true}))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_firewall_rule(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router] [rule]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network router firewall rule.\n" +
          "[router] is required. This is the name or id of an existing network router."
          "[rule] is required. This is the name or id of an existing network router firewall rule."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      router = find_router(args[0])
      return if !router

      rule = router['firewall'] && router['firewall']['rules'] ? router['firewall']['rules'].find {|it| it['name'] == args[1] || it['id'] == args[1].to_i} : nil

      if !rule
        print_red_alert "Firewall rule #{args[1]} not found for router #{router['name']}"
        exit 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the firewall rule '#{rule['name']}' from router '#{router['name']}'?", options)
        return 9, "aborted command"
      end
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.destroy_firewall_rule(router['id'], rule['id'])
        return
      end
      json_response = @network_routers_interface.destroy_firewall_rule(router['id'], rule['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "\nFirewall rule #{rule['name']} for router #{router['name']} is being removed...\n"
        _firewall(router['id'], options.merge({:rules_only => true}))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def dhcp(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display network router DHCP details." + "\n" +
          "[router] is required. This is the name or id of a network router."
    end

    optparse.parse!(args)
    connect(options)

    if args.count < 1
      puts optparse
      return 1
    end

    begin
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_routers_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_routers_interface.dry.list({name:args[0]})
        end
        return
      end
      router = find_router(args[0])
      if router.nil?
        return 1
      end

      json_response = {'networkRouter' => router}

      if options[:json]
        puts as_json(json_response, options, "networkRouter")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkRouter")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['networkRouter']], options)
        return 0
      end

      print_h1 "Network Router DHCP Details for: #{router['name']}"
      print cyan

      if router['type']['hasDhcp']
        print_dhcp(router, true)
      else
        print_red_alert "DHCP not supported for #{router['type']['name']}"
      end
      println reset
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def routes(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network router routes." + "\n" +
          "[router] is required. This is the name or id of a network router."
    end

    optparse.parse!(args)
    connect(options)

    if args.count < 1
      puts optparse
      return 1
    end
    _routes(args[0], options)
  end

  def _routes(router_id, options)
    begin
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_routers_interface.dry.get(router_id.to_i)
        else
          print_dry_run @network_routers_interface.dry.list({name:router_id})
        end
        return
      end
      router = find_router(router_id)
      if router.nil?
        return 1
      end

      json_response = {'networkRouter' => router}

      if options[:json]
        puts as_json(json_response, options, "networkRouter")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkRouter")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['networkRouter']], options)
        return 0
      end

      print_h1 "Network Router Routes for: #{router['name']}"
      print cyan

      if router['type']['hasRouting']
        print_routes(router)
      else
        print_red_alert "Routes not supported for #{router['type']['name']}"
      end
      print reset
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add_route(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[router] [name]")
      opts.on('-n', '--name VALUE', String, "Name for this route") do |val|
        params['name'] = val
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to enable / disable the route. Default is on") do |val|
        options[:enabled] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--default [on|off]', String, "Can be used to enable / disable as default route. Default is off") do |val|
        options[:defaultRoute] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--source VALUE', String, "Network for this route") do |val|
        params['source'] = val
      end
      opts.on('--destination VALUE', String, "Next hop for this route") do |val|
        params['destination'] = val
        end
      opts.on('--mtu VALUE', String, "MTU for this route") do |val|
        params['networkMtu'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network router route."
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if args.count > 1
      params['name'] = args[1]
    end
    begin
      router = find_router(args[0])

      if router.nil?
        return 1
      end

      if !router['type']['hasRouting']
        print_red_alert "Routes not supported for #{router['type']['name']}"
        return 1
      end

      if options[:payload]
        payload = options[:payload]
      else
        params['name'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true}], options[:options], @api_client, params)['name']
        params['description'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => true}], options[:options], @api_client, params)['description']

        # prompt for enabled if not set
        params['enabled'] = options[:enabled].nil? ? Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'description' => 'Enabling Route.', 'defaultValue' => true, 'required' => false}], options, @api_client, {})['enabled'] == 'on' : options[:enabled]

        # default ruote
        params['defaultRoute'] = options[:defaultRoute].nil? ? Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'defaultRoute', 'fieldLabel' => 'Default Route', 'type' => 'checkbox', 'description' => 'Default Route.', 'defaultValue' => false, 'required' => false}], options, @api_client, {})['defaultRoute'] == 'on' : options[:defaultRoute]

        params['source'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'source', 'type' => 'text', 'fieldLabel' => 'Network', 'required' => true}], options[:options], @api_client, params)['source']
        params['destination'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'destination', 'type' => 'text', 'fieldLabel' => 'Next Hop', 'required' => true}], options[:options], @api_client, params)['destination']
        params['networkMtu'] ||= Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkMtu', 'type' => 'text', 'fieldLabel' => 'MTU', 'required' => true}], options[:options], @api_client, params)['networkMtu']

        payload = {'route' => params}
      end

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.create_route(router['id'], payload)
        return
      end

      json_response = @network_routers_interface.create_route(router['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response), "\n"
        return
      end
      print_green_success "\nAdded Network Router Route #{payload['route']['name']}"
      _routes(router['id'], options)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_route(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[router] [rule]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network router route.\n" +
          "[router] is required. This is the name or id of an existing network router."
      "[route] is required. This is the name or id of an existing network router route."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      router = find_router(args[0])
      return if !router

      route = router['routes'] ? router['routes'].find {|it| it['name'] == args[1] || it['id'] == args[1].to_i} : nil

      if !route
        print_red_alert "Route #{args[1]} not found for router #{router['name']}"
        exit 1
      end

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the route '#{route['name']}' from router '#{router['name']}'?", options)
        return 9, "aborted command"
      end
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.destroy_route(router['id'], route['id'])
        return
      end
      json_response = @network_routers_interface.destroy_route(router['id'], route['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "\nRoute #{route['name']} for router #{router['name']} is being removed..."
        _routes(router['id'], options)
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "List network router types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.types(params)
        return
      end

      json_response = @network_routers_interface.types(params)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end

      title = "Morpheus Network Router Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      router_types = json_response['networkRouterTypes']

      if router_types.empty?
        println yellow,"No network router types found.",reset
      else
        print as_pretty_table(router_types, {'ID' => 'id', 'NAME' => 'name'}, options)
      end
      println reset
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def type(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      opts.on('-t', '--type VALUE', String, "Name or ID of router type") do |val|
        options[:options]['routerType'] = val
      end
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
      opts.footer = "Display network router type details."
    end
    optparse.parse!(args)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    if args.count > 0
      options[:options]['routerType'] = args[0]
    end

    begin
      connect(options)
      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.types(params)
        return
      end

      router_type = prompt_router_type(options)

      if options[:json]
        print JSON.pretty_generate({'networkRouterType' => router_type})
        print "\n"
        return
      end

      print_h1 "Network Router Type Details for: #{router_type['name']}"
      print cyan

      description_cols = {
          "ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Code" => lambda {|it| it['code'] },
          "Enabled" => lambda {|it| format_boolean(it['enabled'])},
          "Creatable" => lambda {|it| format_boolean(it['creatable'])},
          "Selectable" => lambda {|it| format_boolean(it['selectable'])},
          "Firewall" => lambda {|it| format_boolean(it['hasFirewall'])},
          "DHCP" => lambda {|it| format_boolean(it['hasDhcp'])},
          "Routing" => lambda {|it| format_boolean(it['hasRouting'])},
          "Network Server" => lambda {|it| format_boolean(it['hasNetworkServer'])}
      }
      print_description_list(description_cols, router_type)

      if router_type['optionTypes'].count > 0
        println cyan
        print Morpheus::Cli::OptionTypes.display_option_types_help(
            router_type['optionTypes'].reject {|it| ['enabled'].include?(it['fieldName'])},
            {:include_context => true, :context_map => {'networkRouter' => ''}, :color => cyan, :title => "Available Router Options"}
        )
      end
      print reset
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_permissions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[router]")
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network router permissions.\n" +
          "[router] is required. This is the name or id of an existing network router."
    end

    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    begin
      if !is_master_account
        print_red_alert "Permissions only available for master tenant"
        return 1
      end

      router = find_router(args[0])
      return 1 if router.nil?

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['permissions'] ||= {}
          payload['permissions'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        perms = {}
        if !options[:visibility].nil?
          perms['visibility'] = options[:visibility]
        end
        if !options[:tenants].nil?
          perms['tenantPermissions'] = {'accounts' => options[:tenants].collect {|id| id.to_i}}
        end
        payload = {'permissions' => perms}
      end

      @network_routers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_routers_interface.dry.update_permissions(router['id'], payload)
        return
      end
      json_response = @network_routers_interface.update_permissions(router['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        print_green_success "\nUpdated Network Router Permissions\n"
      else
        print_rest_errors(json_response, options)
      end
    end
  end

  private

  def print_firewall(router, details=false, rules_only=false)
    if router['type']['hasFirewall']
      if router['firewall']
        if details
          description_cols = {
              "Network Router" => lambda {|it| it['name'] },
              "Enabled" => lambda {|it| format_boolean(it['firewall']['enabled'])},
              "Version" => lambda {|it| it['firewall']['version']},
              "Default Policy" => lambda {|it| (router['firewall']['defaultPolicy'] || {})['action']}
          }
          (router['firewall']['global'] || {}).each do |k,v|
            description_cols[k.gsub(/[A-Z]/, ' \0').downcase] = lambda {|it| it['firewall']['global'][k]}
          end

          if !rules_only
            print_description_list(description_cols, router)
            print_h2 "Firewall Rules"
          end

          if (router['firewall']['rules'] || []).count > 0
            rows = router['firewall']['rules'].collect do |it|
              {
                  id: it['id'],
                  name: it['name'],
                  type: it['ruleType'],
                  policy: it['policy'],
                  direction: it['direction'] || 'any',
                  source: it['source'] || 'any',
                  destination: it['destination'] || 'any',
                  application: it['applications'].count > 0 ? it['applications'][0]['name'] : "#{(it['protocol'] || 'any')} #{it['portRange'] || ''}"
              }
            end
            puts as_pretty_table(rows, [:id, :name, :type, :policy, :direction, :source, :destination, :application])
          else
            println "No firewall rules"
          end
        else
          print "Enabled: #{format_boolean(router['firewall']['enabled'])}".center(20)
          print "Version: #{router['firewall']['version']}".center(20)
          print "Default Policy: #{(router['firewall']['defaultPolicy'] || {})['action']}".center(20)
          println
        end
      else
        println "Enabled: #{format_boolean(false)}".center(20)
      end
    end
  end

  def print_dhcp(router, details=false)
    if router['type']['hasDhcp']
      if router['dhcp']
        if details
          description_cols = {
              "Network Router" => lambda {|it| it['name'] },
              "Enabled" => lambda {|it| format_boolean(it['dhcp']['enabled'])},
              "Version" => lambda {|it| it['dhcp']['version']},
              "Feature" => lambda {|it| it['dhcp']['featureType']},
              "Logs Enabled" => lambda {|it| format_boolean((it['dhcp']['logging'] || {})['enable'])},
              "Log Level" => lambda {|it| (it['dhcp']['logging'] || {})['logLevel']}
          }

          print_description_list(description_cols, router)

          print_h2 "IP Pools"
          print cyan

          if (router['dhcp']['ipPools'] || []).count > 0
            rows = router['dhcp']['ipPools'].collect do |it|
              {
                  ip_range: it['ipRange'],
                  gateway: it['defaultGateway'],
                  subnet: it['subnetMask'],
                  dns: it['primaryNameServer'],
                  domain: it['domainName']
              }
            end
            puts as_pretty_table(rows, [:ip_range, :gateway, :subnet, :dns, :domain])
          else
            println "No IP pools"
          end
        else
          print "Enabled: #{format_boolean(router['dhcp']['enabled'])}".center(20)
          print "Version: #{router['dhcp']['version']}".center(20)
          print "Feature: #{router['dhcp']['version']}".center(20)
          print "Logs Enabled: #{(format_boolean((router['dhcp']['logging'] || {})['enable']))}".center(20)
          print "Log Level: #{(router['dhcp']['logging'] || {})['logLevel']}".center(20)
          println
        end
      else
        print "Enabled: #{format_boolean(false)}".center(20)
        print "Logs Enabled: #{format_boolean(false)}".center(20)
        println
      end
    end
  end

  def print_routes(router)
    if router['type']['hasRouting']
      if router['routes'].count > 0
        rows = router['routes'].collect do |it|
          {
              id: it['id'],
              name: it['name'],
              network: it['source'],
              next_hop: it['destination'],
              interface: it['externalInterface'],
              default_route: format_boolean(it['defaultRoute']),
              mtu: it['networkMtu']
          }
        end
        puts as_pretty_table(rows, [:id, :name, :network, :next_hop, :interface, :default_route, :mtu])
      else
        println "No routes\n"
      end
    end
  end

  def format_router_status(router, return_color = cyan)
    status = router['status']
    color = white
    color = green if status == 'ok'
    color = yellow if status == 'warning'
    color = red if status == 'error'
    "#{color}#{status.upcase}#{return_color}"
  end

  def router_integration_label(router)
    integration = router['networkServer']['integration'] || {}
    integration['integrationType'] ? integration['integrationType']['name'] : router['zone']['name']
  end

  def find_router(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_router_by_id(val)
    else
      return find_router_by_name(val)
    end
  end

  def find_router_by_id(id)
    begin
      json_response = @network_routers_interface.get(id.to_i)
      return json_response['networkRouter']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Router not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_router_by_name(name)
    json_response = @network_routers_interface.list({phrase: name.to_s})
    routers = json_response['networkRouters']
    if routers.empty?
      print_red_alert "Network Router not found by name #{name}"
      return nil
    elsif routers.size > 1
      print_red_alert "#{routers.size} network routers found by name #{name}"
      rows = routers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return routers[0]
    end
  end

  def find_router_type(val)
    types = @network_routers_interface.types()['networkRouterTypes']
    (val.to_s =~ /\A\d{1,}\Z/) ? types.find {|it| it['id'].to_i == val.to_i} : types.find {|it| it['name'] == val}
  end

  def prompt_router_type(options)
    if options[:options]['routerType']
      router_type = find_router_type(options[:options]['routerType'])
      if router_type.nil?
        print_red_alert "Network router type #{options[:options]['routerType']} not found"
        exit 1
      end
    else
      router_types = @network_routers_interface.types()['networkRouterTypes']
      router_type_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'routerType', 'type' => 'select', 'fieldLabel' => 'Network Router Type', 'required' => true, 'selectOptions' => router_types.collect {|it| {'name' => it['name'], 'value' => it['id']}}}], options[:options], @api_client,{}, nil, true)['routerType']
      router_type = router_types.find {|type| type['id'] == router_type_id}
    end
    router_type
  end

  def available_groups()
    @network_routers_interface.groups
  end
end
