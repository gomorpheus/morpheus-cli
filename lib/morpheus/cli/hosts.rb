# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/mixins/logs_helper'
require 'morpheus/cli/option_types'
require 'json'

class Morpheus::Cli::Hosts
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::LogsHelper
  set_command_name :hosts
  set_command_description "View and manage hosts (servers)."
  register_subcommands :list, :count, :get, :view, :stats, :add, :update, :remove, :logs, :start, :stop, :resize, :run_workflow, :make_managed, :upgrade_agent
  register_subcommands :'types' => :list_types
  register_subcommands :exec => :execution_request
  register_subcommands :wiki, :update_wiki
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
    @server_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).server_types
    @logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
    @accounts_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).accounts
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    @execution_request_interface = @api_client.execution_request
    @clusters_interface = @api_client.clusters
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
      opts.on( '--cluster CLUSTER', '--cluster CLUSTER', "Filter by Cluster Name or ID" ) do |val|
        # params[:clusterId] = val
        options[:cluster] = val
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
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:details] = true
      end
      opts.on('--tag-compliant', "Displays only servers that are valid according to applied tag policies. Does not show servers that do not have tag policies." ) do
        params[:tagCompliant] = true
      end
      opts.on('--non-tag-compliant', "Displays only servers with tag compliance warnings." ) do
        params[:tagCompliant] = false
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
      
      cluster = nil
      if options[:cluster]
        if options[:cluster].to_s =~ /\A\d{1,}\Z/
          params['clusterId'] = options[:cluster]
        else
          cluster = find_cluster_by_name_or_id(options[:cluster])
          return 1 if cluster.nil?
          params['clusterId'] = cluster['id']
        end
      end

      @servers_interface.setopts(options)
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
        if cluster
          subtitles << "Cluster: #{cluster['name']}".strip
        elsif params['clusterId']
          subtitles << "Cluster: #{params['clusterId']}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if servers.empty?
          print cyan,"No hosts found.",reset,"\n"
        else
          # print_servers_table(servers)
          # server returns stats in a separate key stats => {"id" => {} }
          # the id is a string right now..for some reason..
          all_stats = json_response['stats'] || {} 
          servers.each do |it|
            found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
            if found_stats
              if !it['stats']
                it['stats'] = found_stats # || {}
              else
                it['stats'] = found_stats.merge!(it['stats'])
              end
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
            if options[:details]
              if stats['maxMemory'] && stats['maxMemory'].to_i != 0
                memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(8, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
              end
              if stats['maxStorage'] && stats['maxStorage'].to_i != 0
                storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(8, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
              end
            end
            row = {
              id: server['id'],
              tenant: server['account'] ? server['account']['name'] : server['accountId'],
              name: server['name'],
              platform: server['serverOs'] ? server['serverOs']['name'].upcase : 'N/A',
              cloud: server['zone'] ? server['zone']['name'] : '',
              type: server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged',
              nodes: server['containers'] ? server['containers'].size : '',
              status: format_server_status(server, cyan),
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
          columns += [:cpu, :memory, :storage]
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
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
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
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:details] = true
      end
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of hosts."
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
      @servers_interface.setopts(options)
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
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
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
      @servers_interface.setopts(options)
      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @servers_interface.dry.get(arg.to_i)
        else
          print_dry_run @servers_interface.dry.list({name: arg})
        end
        return
      end
      json_response = nil
      if arg.to_s =~ /\A\d{1,}\Z/
        json_response = @servers_interface.get(arg.to_i)
      else
        server = find_host_by_name_or_id(arg)
        json_response = @servers_interface.get(server['id'])
        # json_response = {"server" => server} need stats
      end
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
        "Status" => lambda {|it| format_server_status(it) },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].size : 0 },
        "Power" => lambda {|it| format_server_power_state(it) },
      }, server)
      
      if server['statusMessage']
        print_h2 "Status Message", options
        if server['status'] == 'failed'
          print red, server['statusMessage'], reset
        else
          print server['statusMessage']
        end
        print "\n"
      end
      if server['errorMessage']
        print_h2 "Error Message", options
        print red, server['errorMessage'], reset, "\n"
      end

      print_h2 "Host Usage", options
      print_stats_usage(stats)
      print reset, "\n"


      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(server['status'])
          print cyan
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
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
      @servers_interface.setopts(options)
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
      puts cyan + "Status: ".rjust(12) + format_server_status(server).to_s
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
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
      opts.on('--level VALUE', String, "Log Level. DEBUG,INFO,WARN,ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : val
      end
      opts.on('--table', '--table', "Format ouput as a table.") do
        options[:table] = true
      end
      opts.on('-a', '--all', "Display all details: entire message." ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      server = find_host_by_name_or_id(args[0])
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['order'] = params['direction'] unless params['direction'].nil? # old api version expects order instead of direction
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.server_logs([server['id']], params)
        return
      end
      json_response = @logs_interface.server_logs([server['id']], params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result
      
      title = "Host Logs: #{server['name']} (#{server['computeServerType'] ? server['computeServerType']['name'] : 'unmanaged'})"
      subtitles = parse_list_subtitles(options)
      if options[:start]
        subtitles << "Start: #{options[:start]}".strip
      end
      if options[:end]
        subtitles << "End: #{options[:end]}".strip
      end
      if params[:query]
        subtitles << "Search: #{params[:query]}".strip
      end
      # if params['containers']
      #   subtitles << "Containers: #{params['containers']}".strip
      # end
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      print_h1 title, subtitles, options
      logs = json_response['data'] || json_response['logs']
      if logs.empty?
        print "#{cyan}No logs found.#{reset}\n"
      else
        print format_log_records(logs, options)
        print_results_pagination({'meta'=>{'total'=>(json_response['total']['value'] rescue json_response['total']),'size'=>logs.size,'max'=>(json_response['max'] || options[:max]),'offset'=>(json_response['offset'] || options[:offset] || 0)}})
      end
      print reset, "\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
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
      opts.on("--security-groups LIST", Integer, "Security Groups, comma sepearated list of security group IDs") do |val|
        options[:security_groups] = val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    connect(options)
    begin
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        #payload.deep_merge!({'server' => passed_options}) unless passed_options.empty?
        payload.deep_merge!(passed_options) unless passed_options.empty?
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
          print_red_alert "Server Type #{server_type_code} not found for cloud #{cloud['name']}"
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

        # uh ok, this actually expects config at root level, sibling of server 
        # payload.deep_merge!({'server' => passed_options}) unless passed_options.empty?
        payload.deep_merge!(passed_options) unless passed_options.empty?
        payload.deep_merge!({'server' => {
          'name' => host_name,
          'zone' => {'id' => cloud['id']},
          'computeServerType' => {'id' => server_type['id']},
          'plan' => {'id' => service_plan["id"]}
          }
        })

        option_type_list = server_type['optionTypes']

        # remove cpu and memory option types, which now come from the plan
        option_type_list = reject_service_plan_option_types(option_type_list)

        # prompt for resource pool
        pool_id = nil
        has_zone_pools = server_type["provisionType"] && server_type["provisionType"]["hasZonePools"]
        if has_zone_pools
          # pluck out the resourcePoolId option type to prompt for..why the heck is this even needed? 
          resource_pool_option_type = option_type_list.find {|opt| ['resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
          option_type_list = option_type_list.reject {|opt| ['resourcePool','resourcePoolId','azureResourceGroupId'].include?(opt['fieldName']) }
          resource_pool_option_type ||= {'fieldContext' => 'config', 'fieldName' => 'resourcePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'optionSource' => 'zonePools', 'required' => true, 'skipSingleOption' => true, 'description' => 'Select resource pool.'}
          resource_pool_prompt = Morpheus::Cli::OptionTypes.prompt([resource_pool_option_type],options[:options],api_client,{groupId: group_id, siteId: group_id, zoneId: cloud_id, cloudId: cloud_id, planId: service_plan["id"], serverTypeId: server_type['id']})
          resource_pool_prompt.deep_compact!
          payload.deep_merge!(resource_pool_prompt)
          if resource_pool_option_type['fieldContext'] && resource_pool_prompt[resource_pool_option_type['fieldContext']]
            pool_id = resource_pool_prompt[resource_pool_option_type['fieldContext']][resource_pool_option_type['fieldName']]
          elsif resource_pool_prompt[resource_pool_option_type['fieldName']]
            pool_id = resource_pool_prompt[resource_pool_option_type['fieldName']]
          end
        end

        # prompt for volumes
        volumes = prompt_volumes(service_plan, options, @api_client, {zoneId: cloud_id, serverTypeId: server_type['id'], siteId: group_id})
        if !volumes.empty?
          payload['volumes'] = volumes
        end

        # prompt for network interfaces (if supported)
        if server_type["provisionType"] && server_type["provisionType"]["id"] && server_type["provisionType"]["hasNetworks"]
          begin
            network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], pool_id, options)
            if !network_interfaces.empty?
              payload['networkInterfaces'] = network_interfaces
            end
          rescue RestClient::Exception => e
            print yellow,"Unable to load network options. Proceeding...",reset,"\n"
            print_rest_exception(e, options) if Morpheus::Logging.debug?
          end
        end

        # Security Groups
        # prompt for multiple security groups
        sg_option_type = option_type_list.find {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['name'] == 'securityId')) }
        option_type_list = option_type_list.reject {|opt| ((opt['code'] == 'provisionType.amazon.securityId') || (opt['name'] == 'securityId')) }
        # ok.. seed data has changed and serverTypes do not have this optionType anymore...
        if sg_option_type.nil?
          if server_type["provisionType"] && (server_type["provisionType"]["code"] == 'amazon')
            sg_option_type = {'fieldContext' => 'config', 'fieldName' => 'securityId', 'type' => 'select', 'fieldLabel' => 'Security Group', 'optionSource' => 'amazonSecurityGroup', 'required' => true, 'description' => 'Select security group.'}
          end
        end
        has_security_groups = !!sg_option_type
        if options[:security_groups]
          payload['securityGroups'] = options[:security_groups].collect {|sg_id| {'id' => sg_id} }
        else
          if has_security_groups
            security_groups_array = prompt_security_groups(sg_option_type, {zoneId: cloud_id, poolId: pool_id}, options)
            if !security_groups_array.empty?
              payload['securityGroups'] = security_groups_array.collect {|sg_id| {'id' => sg_id} }
            end
          end
        end
    
        api_params = {}
        api_params['zoneId'] = cloud['id']
        api_params['poolId'] = payload['config']['resourcePool'] if (payload['config'] && payload['config']['resourcePool'])
        if payload['config']
          api_params.deep_merge!(payload['config'])
        end
        #api_params.deep_merge(payload)
        params = Morpheus::Cli::OptionTypes.prompt(option_type_list,options[:options],@api_client, api_params)
        payload.deep_merge!(params)
        
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.create(payload)
        return
      end
      json_response = @servers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        server_id = json_response["server"]["id"]
        server_name = json_response["server"]["name"]
        print_green_success "Provisioning host [#{server_id}] #{server_name}"
        # print details
        get_args = [server_id] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
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
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      params.deep_merge!(passed_options) unless passed_options.empty?
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
          print_red_alert "Specify at least one option to update"
          puts optparse
          return 1
        end
        payload = {}
        payload['server'] = params
      end

      @servers_interface.setopts(options)
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
      @servers_interface.setopts(options)
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
      @servers_interface.setopts(options)
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
      @servers_interface.setopts(options)
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
      #     network_interfaces = prompt_network_interfaces(cloud['id'], server_type["provisionType"]["id"], null, options)
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
      @servers_interface.setopts(options)
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

  def make_managed(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_option_type_options(opts, options, make_managed_option_types(false))
      opts.on('--install-agent [on|off]', String, "Install Agent? Pass false to manually install agent. Default is true.") do |val|
        options['installAgent'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('-g', '--group GROUP', String, "Group to assign to new instance.") do |val|
        options[:group] = val
      end
      # opts.on('--instance-type-id ID', String, "Instance Type ID for the new instance.") do |val|
      #   options['instanceTypeId'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      # end
      build_common_options(opts, options, [:options, :json, :dry_run, :quiet, :remote])
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
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload.deep_merge!(passed_options)
      params = Morpheus::Cli::OptionTypes.prompt(make_managed_option_types, options[:options], @api_client, options[:params])
      server_os = params.delete('serverOs')
      if server_os
        payload['server']['serverOs'] = {id: server_os}
      end
      account_id = params.delete('account') # not yet implemented
      if account_id
        payload['server']['account'] = {id: account}
      end
      if options[:group]
        group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil
        return 1 if group.nil?
        params['provisionSiteId'] = group['id']
      end
      payload['server'].merge!(params)
      ['installAgent','instanceTypeId'].each do |k|
        if options[k] != nil
          payload[k] = options[k]
        end
      end
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run(@servers_interface.dry.make_managed(host['id'], payload), options)
        return 0
      end
      json_response = @servers_interface.make_managed(host['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Host #{host['name']} is being converted to managed."
        puts "Public Key:\n#{json_response['publicKey']}\n(copy to your authorized_keys file)"
      end
      return 0
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
      @servers_interface.setopts(options)
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
    workflow = find_workflow_by_name_or_id(args[1])
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
      task_types = @tasks_interface.list_types()
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
      @servers_interface.setopts(options)
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
      @servers_interface.setopts(options)
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
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId'], "--refresh"]+ (options[:remote] ? ["-r",options[:remote]] : []))
      else
        Morpheus::Cli::ExecutionRequestCommand.new.handle(["get", execution_request['uniqueId']]+ (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def server_types_for_cloud(cloud_id, options)
    connect(options)
    zone = find_zone_by_name_or_id(nil, cloud_id)
    cloud_type = cloud_type_for_id(zone['zoneTypeId'])
    cloud_server_types = cloud_type['serverTypes'].select{|b| b['creatable'] == true}
    cloud_server_types = cloud_server_types.sort { |x,y| x['displayOrder'] <=> y['displayOrder'] }
    if options[:json]
      print JSON.pretty_generate(cloud_server_types)
      print "\n"
    else
      print_h1 "Morpheus Server Types - Cloud: #{zone['name']}", [], options
      if cloud_server_types.nil? || cloud_server_types.empty?
        print cyan,"No server types found for the selected cloud",reset,"\n"
      else
        cloud_server_types.each do |server_type|
          print cyan, "[#{server_type['code']}]".ljust(20), " - ", "#{server_type['name']}", "\n"
        end
      end
      print reset,"\n"
    end
  end

  def list_types(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List host types."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      if options[:cloud]
        #return server_types_for_cloud(options[:cloud], options)
        zone = find_zone_by_name_or_id(nil, options[:cloud])
        params["zoneTypeId"] = zone['zoneTypeId']
        params["creatable"] = true
      end
      @server_types_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @server_types_interface.dry.list(params)
        return
      end
      json_response = @server_types_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'serverTypes')
      return 0 if render_result

      server_types = json_response['serverTypes']

      title = "Morpheus Server Types"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      if options[:cloud]
        subtitles << "Cloud: #{options[:cloud]}"
      end
      print_h1 title, subtitles
      if server_types.empty?
        print cyan,"No server types found.",reset,"\n"
      else
        rows = server_types.collect do |server_type|
          {
            id: server_type['id'],
            code: server_type['code'],
            name: server_type['name']
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

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('-w','--wiki', "Open the wiki tab for this host") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View a host in a web browser" + "\n" +
                    "[host] is required. This is the name or id of a host. Supports 1-N [host] arguments."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _view(arg, options)
    end
  end

  def _view(arg, options={})
    begin
      host = find_host_by_name_or_id(arg)
      return 1 if host.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/servers/#{host['id']}"
      if options[:link_tab]
        link << "#!#{options[:link_tab]}"
      end

      if options[:dry_run]
        puts Morpheus::Util.open_url_command(link)
        return 0
      end
      return Morpheus::Util.open_url(link)
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def wiki(args)
    options = {}
    params = {}
    open_wiki_link = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[host]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for a host." + "\n" +
                    "[host] is required. This is the name or id of a host."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?


      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.wiki(host["id"], params)
        return
      end
      json_response = @servers_interface.wiki(host["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Host Wiki Page: #{host['name']}"
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
      opts.footer = "View host wiki page in a web browser" + "\n" +
                    "[host] is required. This is the name or id of a host."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/servers/#{host['id']}#!wiki"

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
      opts.banner = subcommand_usage("[host] [options]")
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
      host = find_host_by_name_or_id(args[0])
      return 1 if host.nil?
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
      @servers_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @servers_interface.dry.update_wiki(host["id"], payload)
        return
      end
      json_response = @servers_interface.update_wiki(host["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for host #{host['name']}"
        wiki([host['id']])
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
      json_results = @clouds_interface.list({groupId: group_id, name: val})
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
    cloud_types = @clouds_interface.cloud_types({max:1000})['zoneTypes']
    cloud_type = cloud_types.find { |z| z['id'].to_i == id.to_i}
    if cloud_type.nil?
      print_red_alert "Cloud Type not found by id #{id}"
      exit 1
    end
    return cloud_type
  end

  def find_cluster_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      find_cluster_by_id(val)
    else
      find_cluster_by_name(val)
    end
  end

  def find_cluster_by_id(id)
    json_results = @clusters_interface.get(id.to_i)
    if json_results['cluster'].empty?
      print_red_alert "Cluster not found by id #{id}"
      exit 1
    end
    json_results['cluster']
  end

  def find_cluster_by_name(name)
    json_results = @clusters_interface.list({name: name})
    if json_results['clusters'].empty? || json_results['clusters'].count > 1
      print_red_alert "Cluster not found by name #{name}"
      exit 1
    end
    json_results['clusters'][0]
  end

  def format_server_power_state(server, return_color=cyan)
    out = ""
    if server['powerState'] == 'on'
      out << "#{green}ON#{return_color}"
    elsif server['powerState'] == 'off'
      out << "#{red}OFF#{return_color}"
    else
      out << "#{white}#{server['powerState'].to_s.upcase}#{return_color}"
    end
    out
  end

  def format_server_status(server, return_color=cyan)
    out = ""
    status_string = server['status']
    # todo: colorize, upcase?
    out << status_string.to_s
    out
  end

   def make_managed_option_types(connected=true)
    [
      #{'fieldName' => 'account', 'fieldLabel' => 'Account', 'type' => 'select', 'optionSource' => 'accounts', 'required' => true},
      {'fieldName' => 'sshUsername', 'fieldLabel' => 'SSH Username', 'type' => 'text', 'required' => true},
      {'fieldName' => 'sshPassword', 'fieldLabel' => 'SSH Password', 'type' => 'password', 'required' => false},
      {'fieldName' => 'serverOs', 'fieldLabel' => 'OS Type', 'type' => 'select', 'optionSource' => 'osTypes', 'required' => false},
    ]
  end

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

end
