# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Hosts
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  set_command_name :hosts
  set_command_description "View and manage hosts (servers)."
  register_subcommands :list, :count, :get, :stats, :add, :update, :remove, :logs, :start, :stop, :resize, :run_workflow, {:'make-managed' => :install_agent}, :upgrade_agent, :server_types
  register_subcommands :exec => :execution_request
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @users_interface = @api_client.users
    @clouds_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).clouds
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @tasks_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).tasks
    @task_sets_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).task_sets
    @servers_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).servers
    @logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @active_group_id = Morpheus::Cli::Groups.active_group
    @execution_request_interface = @api_client.execution_request
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-a', '--account ACCOUNT', "Account Name or ID" ) do |val|
        options[:account] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-M', '--managed', "Show only Managed Servers" ) do |val|
        params[:managed] = true
      end
      opts.on( '-U', '--unmanaged', "Show only Unmanaged Servers" ) do |val|
        params[:managed] = false
      end
      opts.on( '-t', '--type TYPE', "Show only Certain Server Types" ) do |val|
        params[:serverType] = val
      end
      opts.on( '-p', '--power STATE', "Filter by Power Status" ) do |val|
        params[:powerState] = val
      end
      opts.on( '-i', '--ip IPADDRESS', "Filter by IP Address" ) do |val|
        params[:ip] = val
      end
      opts.on( '', '--vm', "Show only virtual machines" ) do |val|
        params[:vm] = true
      end
      opts.on( '', '--hypervisor', "Show only VM Hypervisors" ) do |val|
        params[:vmHypervisor] = true
      end
      opts.on( '', '--container', "Show only Container Hypervisors" ) do |val|
        params[:containerHypervisor] = true
      end
      opts.on( '', '--baremetal', "Show only Baremetal Servers" ) do |val|
        params[:bareMetalHost] = true
      end
      opts.on( '', '--status STATUS', "Filter by Status" ) do |val|
        params[:status] = val
      end

      opts.on( '', '--agent', "Show only Servers with the agent installed" ) do |val|
        params[:agentInstalled] = true
      end
      opts.on( '', '--noagent', "Show only Servers with No agent" ) do |val|
        params[:agentInstalled] = false
      end
      opts.on( '--created-by USER', "Created By User Username or ID" ) do |val|
        options[:created_by] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List hosts."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      account = nil
      if options[:account]
        account = find_account_by_name_or_id(options[:account])
        if account.nil?
          return 1
        else
          params['accountId'] = account['id']
        end
      end
      group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
      if group
        params['siteId'] = group['id']
      end

      # argh, this doesn't work because group_id is required for options/clouds
      # cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
      cloud = options[:cloud] ? find_zone_by_name_or_id(nil, options[:cloud]) : nil
      if cloud
        params['zoneId'] = cloud['id']
      end

      if options[:created_by]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:created_by])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
      end


      if options[:dry_run]
        print_dry_run @servers_interface.dry.list(params)
        return
      end
      json_response = @servers_interface.list(params)

      if options[:json]
        json_response.delete('stats') if options[:include_fields]
        puts as_json(json_response, options, "servers")
        return 0
      elsif options[:yaml]
        json_response.delete('stats') if options[:include_fields]
        puts as_yaml(json_response, options, "servers")
        return 0
      elsif options[:csv]
        # merge stats to be nice here..
        if json_response['servers']
          all_stats = json_response['stats'] || {}
          json_response['servers'].each do |it|
            it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
          end
        end
        puts records_as_csv(json_response['servers'], options)
        return 0
      else
        servers = json_response['servers']
        multi_tenant = json_response['multiTenant'] == true
        title = "Morpheus Hosts"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud
          subtitles << "Cloud: #{cloud['name']}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if servers.empty?
          print yellow,"No hosts found.",reset,"\n"
        else
          # print_servers_table(servers)
          # server returns stats in a separate key stats => {"id" => {} }
          # the id is a string right now..for some reason..
          all_stats = json_response['stats'] || {} 
          servers.each do |it|
            found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
            if !it['stats']
              it['stats'] = found_stats # || {}
            else
              it['stats'] = found_stats.merge!(it['stats'])
            end
          end

          rows = servers.collect {|server| 
            stats = server['stats']
            
            if !stats['maxMemory']
              stats['maxMemory'] = stats['usedMemory'] + stats['freeMemory']
            end
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            row = {
              id: server['id'],
              tenant: server['account'] ? server['account']['name'] : server['accountId'],
              name: server['name'],
              platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A',
              cloud: server['zone'] ? server['zone']['name'] : '',
              type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged',
              nodes: server['containers'] ? server['containers'].size : '',
              status: format_host_status(server, cyan),
              power: format_server_power_state(server, cyan),
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan,
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, :name, :type, :cloud, :nodes, :status, :power]
          if multi_tenant
            columns.insert(4, :tenant)
          end
          term_width = current_terminal_width()
          if term_width > 170
            columns += [:cpu, :memory, :storage]
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
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
      opts.footer = "Get the number of hosts."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @servers_interface.dry.list(params)
        return
      end
      json_response = @servers_interface.list(params)
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
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_until_status] ||= "provisioned,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_common_options(opts, options, [:json, :csv, :yaml, :fields, :dry_run, :remote])
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

  def _get(arg, options)
    begin
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @servers_interface.dry.get(arg.to_i)
        else
          print_dry_run @servers_interface.dry.list({name: arg})
        end
        return
      end
      server = find_host_by_name_or_id(arg)
      json_response = @servers_interface.get(server['id'])
      if options[:json]
        json_response.delete('stats') if options[:include_fields]
        puts as_json(json_response, options, "server")
        return 0
      elsif options[:yaml]
        json_response.delete('stats') if options[:include_fields]
        puts as_yaml(json_response, options, "server")
        return 0
      end
      if options[:csv]
        puts records_as_csv([json_response['server']], options)
        return 0
      end
      server = json_response['server']
      #stats = server['stats'] || json_response['stats'] || {}
      stats = json_response['stats'] || {}
      title = "Host Details"
      print_h1 title, [], options
      print cyan
      print_description_list({
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        #"Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Type" => lambda {|it| it['computeServerType'] ? it['computeServerType']['name'] : 'unmanaged' },
        "Platform" => lambda {|it| it['serverOs'] ? it['serverOs']['name'].upcase : 'N/A' },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        "Agent" => lambda {|it| it['agentInstalled'] ? "#{server['agentVersion'] || ''} updated at #{format_local_dt(server['lastAgentUpdate'])}" : '(not installed)' },
        "Status" => lambda {|it| format_host_status(it) },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].size : 0 },
        "Power" => lambda {|it| format_server_power_state(it) },
      }, server)
      
      print_h2 "Host Usage", options
      print_stats_usage(stats)
      print reset, "\n"

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(server['status'])
          print cyan
          print cyan, "Refreshing in #{options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stats(args)
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
    ids = args
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _stats(arg, options)
    end
  end

  def _stats(arg, options)
    begin
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @servers_interface.dry.get(arg.to_i)
        else
          print_dry_run @servers_interface.dry.list({name: arg})
        end
        return
      end
      server = find_host_by_name_or_id(arg)
      json_response = @servers_interface.get(server['id'])
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      elsif options[:csv]
        puts records_as_csv([json_response['stats']], options)
        return 0
      end
      server = json_response['server']
      #stats = server['stats'] || json_response['stats'] || {}
      stats = json_response['stats'] || {}
      title = "Host Stats: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})"
      print_h1 title, [], options
      puts cyan + "Power: ".rjust(12) + format_server_power_state(server).to_s
      puts cyan + "Status: ".rjust(12) + format_host_status(server).to_s
      puts cyan + "Nodes: ".rjust(12) + (server['containers'] ? server['containers'].size : '').to_s
      #print_h2 "Host Usage", options
      print_stats_usage(stats, {label_width: 10})

      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:list, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      if options[:dry_run]
        print_dry_run @logs_interface.dry.server_logs([server['id']], params)
        return
      end
      logs = @logs_interface.server_logs([server['id']], params)
      output = ""
      if options[:json]
        output << JSON.pretty_generate(logs)
      else
        title = "Host Logs: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        # todo: startMs, endMs, sorts insteaad of sort..etc
        print_h1 title, subtitles, options
        if logs['data'].empty?
          output << "#{cyan}No logs found.#{reset}\n"
        else
          logs['data'].reverse.each do |log_entry|
            log_level = ''
            case log_entry['level']
            when 'INFO'
              log_level = "#{blue}#{bold}INFO#{reset}"
            when 'DEBUG'
              log_level = "#{white}#{bold}DEBUG#{reset}"
            when 'WARN'
              log_level = "#{yellow}#{bold}WARN#{reset}"
            when 'ERROR'
              log_level = "#{red}#{bold}ERROR#{reset}"
            when 'FATAL'
              log_level = "#{red}#{bold}FATAL#{reset}"
            end
            output << "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}\n"
          end
        end
      end
      print output, reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def server_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud]")
      build_common_options(opts, options, [:json, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    options[:zone] = args[0]
    connect(options)
    params = {}

    zone = find_zone_by_name_or_id(nil, options[:zone])
    cloud_type = cloud_type_for_id(zone['zoneTypeId'])
    cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true}
    cloud_server_types = cloud_server_types.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
    if options[:json]
      print JSON.pretty_generate(cloud_server_types)
      print "\n"
    else
      print_h1 "Morpheus Server Types - Cloud: #{zone['name']}", [], options
      if cloud_server_types.nil? || cloud_server_types.empty?
        print yellow,"No server types found for the selected cloud",reset,"\n"
      else
        cloud_server_types.each do |server_type|
          print cyan, "[#{server_type['code']}]".ljust(20), " - ", "#{server_type['name']}", "\n"
        end
      end
      print reset,"\n"
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cloud]", "[name]")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type TYPE', "Server Type Code" ) do |val|
        options[:server_type_code] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # support old format of `hosts add CLOUD NAME`
        if args[0]
          options[:cloud] = args[0]
        end
        if args[1]
          options[:host_name] = args[1]
        end
        # use active group by default
        options[:group] ||= @active_group_id

        params = {}

        # Group
        group_id = nil
        group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
        if group
          group_id = group["id"]
        else
          # print_red_alert "Group not found or specified!"
          # exit 1
          group_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => get_available_groups(), 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})
          group_id = group_prompt['group']
        end

        # Cloud
        cloud_id = nil
        cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group_id, options[:cloud]) : nil
        if cloud
          cloud_id = cloud["id"]
        else
          available_clouds = get_available_clouds(group_id)
          if available_clouds.empty?
            print_red_alert "Group #{group['name']} has no available clouds"
            exit 1
          end
          cloud_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => available_clouds, 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})
          cloud_id = cloud_prompt['cloud']
          cloud = find_cloud_by_id_for_provisioning(group_id, cloud_id)
        end

        # Zone Type
        cloud_type = cloud_type_for_id(cloud['zoneTypeId'])

        # Server Type
        cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true }.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
        if options[:server_type_code]
          server_type_code = options[:server_type_code]
        else
          server_type_options = cloud_server_types.collect {|it| {'name' => it['name'], 'value' => it['code']} }
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'type' => 'select', 'fieldLabel' => "Server Type", 'selectOptions' => server_type_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Choose a server type.'}], options[:options])
          server_type_code = v_prompt['type']
        end
        server_type = cloud_server_types.find {|it| it['code'] == server_type_code }
        if server_type.nil?
          print_red_alert "Server Type #{server_type_code} not found cloud #{cloud['name']}"
          exit 1
        end

        # Server Name
        host_name = nil
        if options[:host_name]
          host_name = options[:host_name]
        else
          name_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Server Name', 'type' => 'text', 'required' => true}], options[:options])
          host_name = name_prompt['name'] || ''
        end

        payload = {}
        # prompt for service plan
        service_plans_json = @servers_interface.service_plans({zoneId: cloud['id'], serverTypeId: server_type["id"]})
        service_plans = service_plans_json["plans"]
        service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
        plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
        service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['plan'].to_i }

        payload['server'] = {
          'name' => host_name,
          'zone' => {'id' => cloud['id']},
          'computeServerType' => {'id' => server_type['id']},
          'plan' => {'id' => service_plan["id"]}
        }

        # prompt for resource pool
        has_zone_pools = server_type["provisionType"] && server_type["provisionType"]["hasZonePools"]
        if has_zone_pools
          resource_pool_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldContext' => 'config', 'fieldName' => 'resourcePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'optionSource' => 'zonePools', 'required' => true, 'skipSingleOption' => true, 'description' => 'Select resource pool.'}],options[:options],api_client,{groupId: group_id, zoneId: cloud_id, cloudId: cloud_id, planId: service_plan["id"]})
          if resource_pool_prompt['config'] && resource_pool_prompt['config']['resourcePool']
            payload['config'] ||= {}
            payload['config']['resourcePool'] = resource_pool_prompt['config']['resourcePool']
          end
        end

        # prompt for volumes
        volumes = prompt_volumes(service_plan, options, @api_client, {})
        if !volumes.empty?
          payload['volumes'] = volumes
        end

        # prompt for network interfaces (if supported)
        if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
          begin
            network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], options)
            if !network_interfaces.empty?
              payload['networkInterfaces'] = network_interfaces
            end
          rescue RestClient::Exception => e
            print yellow,"Unable to load network options. Proceeding...",reset,"\n"
            print_rest_exception(e, options) if Morpheus::Logging.debug?
          end
        end

        server_type_option_types = server_type['optionTypes']
        # remove volume options if volumes were configured
        if !payload['volumes'].empty?
          server_type_option_types = reject_volume_option_types(server_type_option_types)
        end
        # remove networkId option if networks were configured above
        if !payload['networkInterfaces'].empty?
          server_type_option_types = reject_networking_option_types(server_type_option_types)
        end
        # remove resourcePoolId if it was configured above
        if has_zone_pools
          server_type_option_types = server_type_option_types.reject {|opt| ['resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
        end
        # remove cpu and memory option types, which now come from the plan
        server_type_option_types = reject_service_plan_option_types(server_type_option_types)

        params = Morpheus::Cli::OptionTypes.prompt(server_type_option_types,options[:options],@api_client, {zoneId: cloud['id']})
        payload.deep_merge!(params)
        
      end
      if options[:dry_run]
        print_dry_run @servers_interface.dry.create(payload)
        return
      end
      json_response = @servers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Provisioning Server..." 
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
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['name'] = val == "null" ? nil : val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val == "null" ? nil : val
      end
      opts.on('--ssh-username VALUE', String, "SSH Username") do |val|
        params['sshUsername'] = val == "null" ? nil : val
      end
      opts.on('--ssh-password VALUE', String, "SSH Password") do |val|
        params['sshPassword'] = val == "null" ? nil : val
      end
      opts.on('--power-schedule-type ID', String, "Power Schedule Type ID") do |val|
        params['powerScheduleType'] = val == "null" ? nil : val
      end
      # opts.on('--created-by ID', String, "Created By User ID") do |val|
      #   params['createdById'] = val
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)

    begin
      server = find_host_by_name_or_id(args[0])
      return 1 if server.nil?
      new_group = nil
      params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support args and option parameters on top of payload
        if !params.empty?
          payload['server'] ||= {}
          payload['server'].deep_merge!(params)
        end
      else
        if params.empty?
          print_red_alert "Specify atleast one option to update"
          puts optparse
          return 1
        end
        payload = {}
        payload['server'] = params
      end

      if options[:dry_run]
        print_dry_run @servers_interface.dry.update(server["id"], payload)
        return
      end
      json_response = @servers_interface.update(server["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated host #{server['name']}"
        get([server['id']])
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
      opts.banner = subcommand_usage("[name]")
      # opts.on( '-S', '--skip-remove-infrastructure', "Skip removal of underlying cloud infrastructure. Same as --remove-resources off" ) do
      #   query_params[:removeResources] = 'off'
      # end
      opts.on('--remove-resources [on|off]', ['on','off'], "Remove Infrastructure. Default is on if server is managed.") do |val|
        query_params[:removeResources] = val.nil? ? 'on' : val
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on('--remove-instances [on|off]', ['on','off'], "Remove Associated Instances. Default is off.") do |val|
        query_params[:removeInstances] = val.nil? ? 'on' : val
      end
      opts.on('--release-eips [on|off]', ['on','off'], "Release EIPs, default is on. Amazon only.") do |val|
        params[:releaseEIPs] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      server = find_host_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the server '#{server['name']}'?", options)
        exit 1
      end
      if options[:dry_run]
        print_dry_run @servers_interface.dry.destroy(server['id'], query_params)
        return
      end
      json_response = @servers_interface.destroy(server['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Host #{server['name']} is being removed..."
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start a host.\n" +
                    "[name] is required. This is the name or id of a host. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host_ids = parse_id_list(args)
      hosts = []
      host_ids.each do |host_id|
        host = find_host_by_name_or_id(host_id)
        return 1 if host.nil?
        hosts << host
      end
      objects_label = "#{hosts.size == 1 ? 'host' : (hosts.size.to_s + ' hosts')} #{anded_list(hosts.collect {|it| it['name'] })}"
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{objects_label}?", options)
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @servers_interface.dry.start(hosts.collect {|it| it['id'] })
        return
      end
      json_response = @servers_interface.start(hosts.collect {|it| it['id'] })
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Started #{objects_label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop a host.\n" +
                    "[name] is required. This is the name or id of a host. Supports 1-N [name] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host_ids = parse_id_list(args)
      hosts = []
      host_ids.each do |host_id|
        host = find_host_by_name_or_id(host_id)
        return 1 if host.nil?
        hosts << host
      end
      objects_label = "#{hosts.size == 1 ? 'host' : (hosts.size.to_s + ' hosts')} #{anded_list(hosts.collect {|it| it['name'] })}"
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{objects_label}?", options)
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @servers_interface.dry.stop(hosts.collect {|it| it['id'] })
        return
      end
      json_response = @servers_interface.stop(hosts.collect {|it| it['id'] })
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Stopped #{objects_label}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])

      group_id = server["siteId"] || erver['group']['id']
      cloud_id = server["zoneId"] || server["zone"]["id"]
      server_type_id = server['computeServerType']['id']
      plan_id = server['plan']['id']
      payload = {
        :server => {:id => server["id"]}
      }

      # avoid 500 error
      # payload[:servicePlanOptions] = {}
      unless options[:no_prompt]
        puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"
        # unless hot_resize
        #   puts "\nWARNING: Resize actions for this server will cause instances to be restarted.\n\n"
        # end
      end

      # prompt for service plan
      service_plans_json = @servers_interface.service_plans({zoneId: cloud_id, serverTypeId: server_type_id})
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        if plan['value'] && plan['value'].to_i == plan_id.to_i
          plan['name'] = "#{plan['name']} (current)"
        end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'plan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this server'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['plan'].to_i }
      payload[:server][:plan] = {id: service_plan["id"]}

      # fetch volumes
      volumes_response = @servers_interface.volumes(server['id'])
      current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

      # prompt for volumes
      volumes = prompt_resize_volumes(current_volumes, service_plan, options)
      if !volumes.empty?
        payload[:volumes] = volumes
      end

      # todo: reconfigure networks
      #       need to get provision_type_id for network info
      # prompt for network interfaces (if supported)
      # if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
      #   begin
      #     network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], options)
      #     if !network_interfaces.empty?
      #       payload[:networkInterfaces] = network_interfaces
      #     end
      #   rescue RestClient::Exception => e
      #     print yellow,"Unable to load network options. Proceeding...",reset,"\n"
      #     print_rest_exception(e, options) if Morpheus::Logging.debug?
      #   end
      # end

      # only amazon supports this option
      # for now, always do this
      payload[:deleteOriginalVolumes] = true

      if options[:dry_run]
        print_dry_run @servers_interface.dry.resize(server['id'], payload)
        return
      end
      json_response = @servers_interface.resize(server['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        unless options[:quiet]
          puts "Host #{server['name']} resizing..."
          list([])
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def install_agent(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, install_agent_option_types(false))
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host = find_host_by_name_or_id(args[0])
      if host['agentInstalled']
        print_red_alert "Agent already installed on host '#{host['name']}'"
        return false
      end
      payload = {
        'server' => {}
      }
      params = Morpheus::Cli::OptionTypes.prompt(install_agent_option_types, options[:options], @api_client, options[:params])
      server_os = params.delete('serverOs')
      if server_os
        payload['server']['serverOs'] = {id: server_os}
      end
      account_id = params.delete('account') # not yet implemented
      if account_id
        payload['server']['account'] = {id: account}
      end
      payload['server'].merge!(params)

      if options[:dry_run]
        print_dry_run @servers_interface.dry.install_agent(host['id'], payload)
        return
      end
      json_response = @servers_interface.install_agent(host['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Host #{host['name']} is being converted to managed."
        puts "Public Key:\n#{json_response['publicKey']}\n(copy to your authorized_keys file)"
      end
      return true
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def upgrade_agent(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      host = find_host_by_name_or_id(args[0])
      if options[:dry_run]
        print_dry_run @servers_interface.dry.upgrade(host['id'])
        return
      end
      json_response = @servers_interface.upgrade(host['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        puts "Host #{host['name']} upgrading..." unless options[:quiet]
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def run_workflow(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [workflow] [options]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count != 2
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 2 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    host = find_host_by_name_or_id(args[0])
    return 1 if host.nil?
    workflow = find_workflow_by_name(args[1])
    return 1 if workflow.nil?

    # support -O options as arbitrary params
    old_option_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
    params.deep_merge!(old_option_options) unless old_option_options.empty?

    # the payload format is unusual
    # payload example: {"taskSet": {taskSetId": {"taskSetTaskId": {"customOptions": {"dbVersion":"5.6"}}}}}
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      payload = {}
      # i guess you must pass an option if there are editable options
      # any option, heh
      task_types = @tasks_interface.task_types()
      editable_options = []
      workflow['taskSetTasks'].sort{|a,b| a['taskOrder'] <=> b['taskOrder']}.each do |task_set_task|
        task_type_id = task_set_task['task']['taskType']['id']
        task_type = task_types['taskTypes'].find{ |current_task_type| current_task_type['id'] == task_type_id}
        task_opts = task_type['optionTypes'].select { |otype| otype['editable']}
        if !task_opts.nil? && !task_opts.empty?
          editable_options += task_opts.collect do |task_opt|
            new_task_opt = task_opt.clone
            new_task_opt['fieldContext'] = "#{task_set_task['id']}.#{new_task_opt['fieldContext']}"
          end
        end
      end
      # if params.empty? && !editable_options.empty?
      #   puts optparse
      #   option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
      #   puts "\nAvailable Options:\n#{option_lines}\n\n"
      #   return 1
      # end

    end

    if !params.empty?
      payload['taskSet'] ||= {}
      payload['taskSet']["#{workflow['id']}"] ||= {}
      payload['taskSet']["#{workflow['id']}"].deep_merge!(params)
    end

    begin
      if options[:dry_run]
        print_dry_run @servers_interface.dry.workflow(host['id'],workflow['id'], payload)
        return
      end
      json_response = @servers_interface.workflow(host['id'],workflow['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif options[:quiet]
        return 0
      else
        print_green_success "Running workflow #{workflow['name']} on host #{host['name']} ..."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def execution_request(args)
    options = {}
    params = {}
    script_content = nil
    do_refresh = true
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id] [options]")
      opts.on('--script SCRIPT', "Script to be executed" ) do |val|
        script_content = val
      end
      opts.on('--file FILE', "File containing the script. This can be used instead of --script" ) do |filename|
        full_filename = File.expand_path(filename)
        if File.exists?(full_filename)
          script_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          exit 1
        end
      end
      opts.on(nil, '--no-refresh', "Do not refresh until finished" ) do
        do_refresh = false
      end
      #build_option_type_options(opts, options, add_user_source_option_types())
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an arbitrary command or script on a host." + "\n" +
                    "[id] is required. This is the id a host." + "\n" +
                    "[script] is required. This is the script that is to be executed."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    
    
    begin
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?
      params['serverId'] = host['id']
      # construct payload
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
        # prompt for Script
        if script_content.nil?
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'script', 'type' => 'code-editor', 'fieldLabel' => 'Script', 'required' => true, 'description' => 'The script content'}], options[:options])
          script_content = v_prompt['script']
        end
        payload['script'] = script_content
      end
      # dry run?
      if options[:dry_run]
        print_dry_run @execution_request_interface.dry.create(params, payload)
        return 0
      end
      # do it
      json_response = @execution_request_interface.create(params, payload)
      # print and return result
      if options[:quiet]
        return 0
      elsif options[:json]
        puts as_json(json_response, options)
        return 0
      end
      execution_request = json_response['executionRequest']
      print_green_success "Executing request #{execution_request['uniqueId']}"
      if do_refresh
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId'], "--refresh"])
      else
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  private

  def find_host_by_id(id)
    begin
      json_response = @servers_interface.get(id.to_i)
      return json_response['server']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Host not found by id #{id}"
        exit 1
      else
        raise e
      end
    end
  end

  def find_host_by_name(name)
    results = @servers_interface.list({name: name})
    if results['servers'].empty?
      print_red_alert "Server not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple Servers exist with the name #{name}. Try using id instead"
      exit 1
    end
    return results['servers'][0]
  end

  def find_host_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_host_by_id(val)
    else
      return find_host_by_name(val)
    end
  end

  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      json_results = @clouds_interface.get(val.to_i)
      zone = json_results['zone']
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      json_results = @clouds_interface.get({groupId: group_id, name: val})
      zone = json_results['zones'] ? json_results['zones'][0] : nil
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end

  def find_server_type(zone, name)
    server_type = zone['serverTypes'].select do  |sv_type|
      (sv_type['name'].downcase == name.downcase || sv_type['code'].downcase == name.downcase) && sv_type['creatable'] == true
    end
    if server_type.nil?
      print_red_alert "Server Type Not Selectable"
    end
    return server_type
  end

  def cloud_type_for_id(id)
    cloud_types = @clouds_interface.cloud_types['zoneTypes']
    cloud_type = cloud_types.find { |z| z['id'].to_i == id.to_i}
    if cloud_type.nil?
      print_red_alert "Cloud Type not found by id #{id}"
      exit 1
    end
    return cloud_type
  end

  def find_workflow_by_name(name)
    task_set_results = @task_sets_interface.get(name)
    if !task_set_results['taskSets'].nil? && !task_set_results['taskSets'].empty?
      return task_set_results['taskSets'][0]
    else
      print_red_alert "Workflow not found by name #{name}"
      exit 1
    end
  end


  def format_server_power_state(server, return_color=cyan)
    out = ""
    if server['powerState'] == 'on'
      out << "#{green}ON#{return_color}"
    elsif server['powerState'] == 'off'
      out << "#{red}OFF#{return_color}"
    else
      out << "#{white}#{server['powerState'].upcase}#{return_color}"
    end
    out
  end

  def format_host_status(server, return_color=cyan)
    out = ""
    status_string = server['status']
    # todo: colorize, upcase?
    out << status_string.to_s
    out
  end

   def install_agent_option_types(connected=true)
    [
      #{'fieldName' => 'account', 'fieldLabel' => 'Account', 'type' => 'select', 'optionSource' => 'accounts', 'required' => true},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text', 'required' => true},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false},
      {'fieldName' => 'serverOs', 'fieldLabel' => 'OS Type', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false},
    ]
  end

end
