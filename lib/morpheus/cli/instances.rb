require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::Instances
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper # needed? replace with OptionSourceHelper
  include Morpheus::Cli::OptionSourceHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::DeploymentsHelper
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::LogsHelper

  set_command_name :instances
  set_command_description "View and manage instances."
  register_subcommands :list, :count, :get, :view, :add, :update, :remove, :cancel_removal, :logs, 
                       :history, {:'history-details' => :history_details}, {:'history-event' => :history_event_details}, 
                       :stats, :stop, :start, :restart, :actions, :action, :suspend, :eject, :stop_service, :start_service, :restart_service, 
                       :backup, :backups, :resize, :clone, :envs, :setenv, :delenv, 
                       :security_groups, :apply_security_groups, :run_workflow, :import_snapshot, :snapshots,
                       :console, :status_check, {:containers => :list_containers}, 
                       :scaling, {:'scaling-update' => :scaling_update},
                       :wiki, :update_wiki,
                       {:exec => :execution_request},
                       :deploys
  #register_subcommands :firewall_disable, :firewall_enable
  # register_subcommands {:'lb-update' => :load_balancer_update}
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @users_interface = @api_client.users
    @instances_interface = @api_client.instances
    @task_sets_interface = @api_client.task_sets
    @logs_interface = @api_client.logs
    @tasks_interface = @api_client.tasks
    @instance_types_interface = @api_client.instance_types
    @library_layouts_interface = @api_client.library_layouts
    @clouds_interface = @api_client.clouds
    @clouds_datastores_interface = @api_client.cloud_datastores
    @servers_interface = @api_client.servers
    @provision_types_interface = @api_client.provision_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
    @execution_request_interface = @api_client.execution_request
    @deploy_interface = @api_client.deploy
    @deployments_interface = @api_client.deployments
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-H', '--host HOST', "Host Name or ID" ) do |val|
        options[:host] = val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val
      end
      opts.add_hidden_option('--created-by')
      opts.on('--status STATUS', "Filter by status i.e. provisioning,running,starting,stopping") do |val|
        params['status'] = (params['status'] || []) + val.to_s.split(',').collect {|s| s.strip }.select {|s| s != "" }
      end
      opts.on('--pending-removal', "Include instances pending removal.") do
        options[:showDeleted] = true
      end
      opts.on('--pending-removal-only', "Only instances pending removal.") do
        options[:deleted] = true
      end
      opts.on('--labels label',String, "Filter by labels (keywords).") do |val|
        val.split(",").each do |k|
          options[:labels] ||= []
          options[:labels] << k.strip
        end
      end
      opts.on('--tags Name=Value',String, "Filter by tags (metadata name value pairs).") do |val|
        val.split(",").each do |value_pair|
          k,v = value_pair.strip.split("=")
          options[:tags] ||= {}
          options[:tags][k] ||= []
          options[:tags][k] << (v || '')
        end
      end
      opts.on('--stats', "Display values for memory and storage usage used / max values." ) do
        options[:stats] = true
      end
      opts.on('-a', '--details', "Display all details: plan, stats, etc" ) do
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List instances."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    begin
      params.merge!(parse_list_options(options))
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

      host = options[:host] ? find_host_by_name_or_id(options[:host]) : options[:host]
      if host
        params['serverId'] = host['id']
      end

      account = nil
      #todo: user = find_available_user_option(owner_id)

      if options[:owner]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
        params['ownerId'] = created_by_ids # 4.2.1+
      end

      params['showDeleted'] = true if options[:showDeleted]
      params['deleted'] = true if options[:deleted]
      params['labels'] = options[:labels] if options[:labels]
      if options[:tags]
        options[:tags].each do |k,v|
          params['tags.' + k] = v
        end
      end

      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return 0
      end
      json_response = @instances_interface.list(params)
      if options[:json]
        puts as_json(json_response, options, "instances")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instances")
        return 0
      elsif options[:csv]
        # merge stats to be nice here..
        if json_response['instances']
          all_stats = json_response['stats'] || {}
          if all_stats
            json_response['instances'].each do |it|
              it['stats'] ||= all_stats[it['id'].to_s] || all_stats[it['id']]
            end
          end
        end
        puts records_as_csv(json_response['instances'], options)
      else
        instances = json_response['instances']

        title = "Morpheus Instances"
        subtitles = []
        if group
          subtitles << "Group: #{group['name']}".strip
        end
        if cloud
          subtitles << "Cloud: #{cloud['name']}".strip
        end
        if host
          subtitles << "Host: #{host['name']}".strip
        end
        if options[:owner]
          subtitles << "Created By: #{options[:owner]}"
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if instances.empty?
          print cyan,"No instances found.",reset,"\n"
        else
          # print_instances_table(instances)
          # server returns stats in a separate key stats => {"id" => {} }
          # the id is a string right now..for some reason..
          all_stats = json_response['stats'] || {} 
          if all_stats
            instances.each do |it|
              if !it['stats']
                found_stats = all_stats[it['id'].to_s] || all_stats[it['id']]
                it['stats'] = found_stats # || {}
              end
            end
          end

          rows = instances.collect {|instance| 
            stats = instance['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            if options[:details] || options[:stats]
              if stats['maxMemory'] && stats['maxMemory'].to_i != 0
                memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(8, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
              end
              if stats['maxStorage'] && stats['maxStorage'].to_i != 0
                storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(8, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
              end
            end
            row = {
              id: instance['id'],
              name: instance['name'],
              connection: format_instance_connection_string(instance),
              environment: instance['instanceContext'],
              user: (instance['owner'] ? (instance['owner']['username'] || instance['owner']['id']) : (instance['createdBy'].is_a?(Hash) ? instance['createdBy']['username'] : instance['createdBy'])),
              tenant: (instance['owner'] ? (instance['owner']['username'] || instance['owner']['id']) : (instance['createdBy'].is_a?(Hash) ? instance['createdBy']['username'] : instance['createdBy'])),
              nodes: instance['containers'].count,
              status: format_instance_status(instance, cyan),
              type: instance['instanceType']['name'],
              group: instance['group'] ? instance['group']['name'] : nil,
              cloud: instance['cloud'] ? instance['cloud']['name'] : nil,
              plan: instance['plan'] ? instance['plan']['name'] : '',
              version: instance['instanceVersion'] ? instance['instanceVersion'] : '',
              created: format_local_dt(instance['dateCreated']),
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan, 
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, {:name => {:max_width => 50}}, :group, :cloud, 
              :type, :version, :environment, 
              {:created => {:display_name => "CREATED"}}, 
              # {:tenant => {:display_name => "TENANT"}}, 
              {:user => {:display_name => "OWNER", :max_width => 20}}, 
              :plan,
              :nodes, {:connection => {:max_width => 30}}, :status, :cpu, :memory, :storage]
          # custom pretty table columns ... this is handled in as_pretty_table now(), 
          # todo: remove all these.. and try to always pass rows as the json data itself..
          if options[:details] != true
            columns.delete(:plan)
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
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-H', '--host HOST', "Host Name or ID" ) do |val|
        options[:host] = val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val
      end
      opts.add_hidden_option('--created-by')
      opts.on( '-s', '--search PHRASE', "Search Phrase" ) do |phrase|
        options[:phrase] = phrase
      end
      build_common_options(opts, options, [:query, :remote, :dry_run])
      opts.footer = "Get the number of instances."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
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

      host = options[:host] ? find_host_by_name_or_id(options[:host]) : options[:host]
      if host
        params['serverId'] = host['id']
      end

      account = nil
      if options[:owner]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
        # params['ownerId'] = created_by_ids # 4.2.1+
      end
      
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.list(params)
        return
      end
      json_response = @instances_interface.list(params)
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

  def add(args)
    options = {}
    options[:create_user] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      # opts.banner = subcommand_usage("[type] [name]")
      opts.banner = subcommand_usage("[name] -c CLOUD -t TYPE")
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--type CODE', "Instance Type" ) do |val|
        options[:instance_type_code] = val
      end
      opts.on( '--name NAME', "Instance Name" ) do |val|
        options[:instance_name] = val
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on("--environment ENV", String, "Environment code") do |val|
        options[:environment] = val.to_s
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('--labels LIST', String, "Labels (keywords) in the format 'foo, bar'") do |val|
        options[:labels] = val.split(',').collect {|it| it.to_s.strip }.compact.uniq.join(',')
      end
      opts.on("--copies NUMBER", Integer, "Number of copies to provision") do |val|
        options[:copies] = val.to_i
      end
      opts.on("--layout-size NUMBER", Integer, "Apply a multiply factor of containers/vms within the instance") do |val|
        options[:layout_size] = val.to_i
      end
      opts.on( '-l', '--layout LAYOUT', "Layout ID" ) do |val|
        options[:layout] = val
      end
      opts.on( '-p', '--plan PLAN', "Service plan ID") do |val|
        options[:service_plan] = val
      end
      opts.on( '--resource-pool ID', String, "Resource pool ID" ) do |val|
        options[:resource_pool] = val
      end
      opts.on("--workflow ID", String, "Automation: Workflow ID") do |val|
        options[:workflow_id] = val
      end
      opts.on("--ports ARRAY", String, "Exposed Ports, JSON formatted list of objects containing name and port") do |val|
        # expects format like --ports '[{"name":"web","port":8080}]'
        ports_array = JSON.parse(val)
        options[:ports] = ports_array
        options[:options]['ports'] = ports_array
      end
      # opts.on('-L', "--lb", "Enable Load Balancer") do
      #   options[:enable_load_balancer] = true
      # end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is on") do |val|
        options[:create_user] = !['false','off','0'].include?(val.to_s)
      end
      opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
        options[:user_group_id] = val
      end
      opts.on("--shutdown-days DAYS", Integer, "Automation: Shutdown Days") do |val|
        options[:shutdown_days] = val.to_i
      end
      opts.on("--expire-days DAYS", Integer, "Automation: Expiration Days") do |val|
        options[:expire_days] = val.to_i
      end
      opts.on("--create-backup [on|off]", String, "Automation: Create Backups.") do |val|
        options[:create_backup] = ['on','true','1',''].include?(val.to_s.downcase) ? 'on' : 'off'
      end
      opts.on("--security-groups LIST", String, "Security Groups, comma sepearated list of security group IDs") do |val|
        options[:security_groups] = val.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote, :quiet])
      opts.footer = "Create a new instance." + "\n" +
                    "[name] is required. This is the new instance name." + "\n" +
                    "The available options vary by --type."
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add has just 1 (optional) argument: [name].  Got #{args.count} arguments: #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if args[0]
      options[:instance_name] = args[0]
    end

    # use active group by default
    options[:group] ||= @active_group_id
    options[:select_datastore] = true
    options[:name_required] = true
    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        payload.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]
      else
        # prompt for all the instance configuration options
        # this provisioning helper method handles all (most) of the parsing and prompting
        # and it relies on the method to exit non-zero on error, like a bad CLOUD or TYPE value
        payload = prompt_new_instance(options)
        # clean payload of empty objects 
        # note: this is temporary and should be fixed upstream in OptionTypes.prompt()
        if payload['instance'].is_a?(Hash)
          payload['instance'].keys.each do |k|
            v = payload['instance'][k]
            payload['instance'].delete(k) if v.is_a?(Hash) && v.empty?
          end
        end
        if payload['config'].is_a?(Hash)
          payload['config'].keys.each do |k|
            v = payload['config'][k]
            payload['config'].delete(k) if v.is_a?(Hash) && v.empty?
          end
        end
      end
      payload['instance'] ||= {}
      if options[:instance_name]
        payload['instance']['name'] = options[:instance_name]
      end
      if options[:description] && !payload['instance']['description']
        payload['instance']['description'] = options[:description]
      end
      if options[:environment] && !payload['instance']['instanceContext']
        payload['instance']['instanceContext'] = options[:environment]
      end
      payload[:copies] = options[:copies] if options[:copies] && options[:copies] > 0
      payload[:layoutSize] = options[:layout_size] if options[:layout_size] && options[:layout_size] > 0 # aka Scale Factor
      payload[:createBackup] = options[:create_backup] if !options[:create_backup].nil?
      payload['instance']['expireDays'] = options[:expire_days] if options[:expire_days]
      payload['instance']['shutdownDays'] = options[:shutdown_days] if options[:shutdown_days]
      if options.key?(:create_user)
        payload['config'] ||= {}
        payload['config']['createUser'] = options[:create_user]
      end
      if options[:user_group_id]
        payload['instance']['userGroup'] = {'id' => options[:user_group_id] }
      end
      if options[:workflow_id]
        if options[:workflow_id].to_s =~ /\A\d{1,}\Z/
          payload['taskSetId'] = options[:workflow_id].to_i
        else
          payload['taskSetName'] = options[:workflow_id]
        end
      end
      if options[:enable_load_balancer]
        lb_payload = prompt_instance_load_balancer(payload['instance'], nil, options)
        payload.deep_merge!(lb_payload)
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create(payload)
        return 0
      end

      json_response = @instances_interface.create(payload)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        instance_id = json_response["instance"]["id"]
        instance_name = json_response["instance"]["name"]
        print_green_success "Provisioning instance [#{instance_id}] #{instance_name}"
        # print details
        get_args = [instance_id] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--name VALUE', String, "Name") do |val|
        params['displayName'] = val
      end
      opts.on('--description VALUE', String, "Description") do |val|
        params['description'] = val
      end
      opts.on('--environment VALUE', String, "Environment") do |val|
        params['instanceContext'] = val
      end
      opts.on('--group GROUP', String, "Group Name or ID") do |val|
        options[:group] = val
      end
      opts.on('--tags LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.on('--metadata LIST', String, "Metadata tags in the format 'ping=pong,flash=bang'") do |val|
        options[:metadata] = val
      end
      opts.add_hidden_option('--metadata')
      opts.on('--labels LIST', String, "Labels (keywords) in the format 'foo, bar'") do |val|
        # todo switch this from 'tags' to 'labels'
        params['tags'] = val.split(',').collect {|it| it.to_s.strip }.compact.uniq.join(',')
      end
      opts.on('--power-schedule-type ID', String, "Power Schedule Type ID") do |val|
        params['powerScheduleType'] = val == "null" ? nil : val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val == 'null' ? nil : val
      end
      opts.on( '--created-by USER', "Alias for --owner" ) do |val|
        options[:owner] = val == 'null' ? nil : val
      end
      opts.add_hidden_option('--created-by')
      # opts.on("--shutdown-days [DAYS]", Integer, "Automation: Shutdown Days") do |val|
      #   params['shutdownDays'] = val.to_s.empty? ? nil : val.to_i
      # end
      # opts.on("--expire-days DAYS", Integer, "Automation: Expiration Days") do |val|
      #   params['expireDays'] = val.to_s.empty? ? nil : val.to_i
      # end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      if options[:payload]
        payload = options[:payload]
      end
      payload['instance'] ||= {}
      payload.deep_merge!({'instance' => parse_passed_options(options)})

      if options.key?(:owner) && [nil].include?(options[:owner])
        # allow clearing
        params['ownerId'] = nil
      elsif options[:owner]
        owner_id = options[:owner].to_s
        if owner_id.to_s =~ /\A\d{1,}\Z/
          # allow id without lookup
        else
          user = find_available_user_option(owner_id)
          return 1 if user.nil?
          owner_id = user['id']
        end
        params['ownerId'] = owner_id
        #payload['createdById'] = options[:owner].to_i # pre 4.2.1 api
      end
      if options[:group]
        group = find_group_by_name_or_id_for_provisioning(options[:group])
        if group.nil?
          return 1, "group not found"
        end
        payload['instance']['site'] = {'id' => group['id']}
      end
      # metadata tags
      # if options[:options]['metadata'].is_a?(Array) && !options[:metadata]
      #   options[:metadata] = options[:options]['metadata']
      # end
      if options[:metadata]
        metadata = []
        if options[:metadata] == "[]" || options[:metadata] == "null"
          payload['instance']['metadata'] = []
        elsif options[:metadata].is_a?(Array)
          payload['instance']['metadata'] = options[:metadata]
        else
          # parse string into format name:value, name:value
          # merge IDs from current metadata
          # todo: should allow quoted semicolons..
          metadata_list = options[:metadata].split(",").select {|it| !it.to_s.empty? }
          metadata_list = metadata_list.collect do |it|
            metadata_pair = it.split(":")
            if metadata_pair.size == 1 && it.include?("=")
              metadata_pair = it.split("=")
            end
            row = {}
            row['name'] = metadata_pair[0].to_s.strip
            row['value'] = metadata_pair[1].to_s.strip
            row
          end
          payload['instance']['metadata'] = metadata_list
        end
      end
      if payload['instance'].empty? && params.empty? && options[:owner].nil?
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
      if !params.empty?
        payload['instance'].deep_merge!(params)
      end
      payload.delete('instance') if payload['instance'] && payload['instance'].empty?
      raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated instance #{instance['name']}"
        #list([])
        get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
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
      opts.banner = subcommand_usage("[instance]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for an instance." + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?


      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.wiki(instance["id"], params)
        return
      end
      json_response = @instances_interface.wiki(instance["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "Instance Wiki Page: #{instance['name']}"
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
        return view_wiki([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
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
      opts.footer = "View instance wiki page in a web browser" + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/instances/#{instance['id']}#!wiki"

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

  def update_wiki(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [options]")
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
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
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
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_wiki(instance["id"], payload)
        return
      end
      json_response = @instances_interface.update_wiki(instance["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for instance #{instance['name']}"

        wiki([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def status_check(args)
    out = ""
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:quiet, :json, :remote]) # no :dry_run, just do it man
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    # todo: just return status or maybe check if instance['status'] == args[0]
    instance = find_instance_by_name_or_id(args[0])
    exit_code = 0
    if instance['status'].to_s.downcase != (args[1] || "running").to_s.downcase
      exit_code = 1
    end
    if options[:json]
      mock_json = {status: instance['status'], exit: exit_code}
      out << as_json(mock_json, options)
      out << "\n"
    elsif !options[:quiet]
      out << cyan
      out << "Status: #{format_instance_status(instance)}"
      out << reset
      out << "\n"
    end
    print out unless options[:quiet]
    exit exit_code #return exit_code
  end

  def stats(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
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
      instance = find_instance_by_name_or_id(arg)
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get(instance['id'])
        return 0
      end
      json_response = @instances_interface.get(instance['id'])
      if options[:json]
        puts as_json(json_response, options, "stats")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "stats")
        return 0
      end
      instance = json_response['instance']
      stats = instance['stats'] || json_response['stats'] || {}
      title = "Instance Stats: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      puts cyan + "Status: ".rjust(12) + format_instance_status(instance).to_s
      puts cyan + "Nodes: ".rjust(12) + (instance['containers'] ? instance['containers'].count : '').to_s
      # print "\n"
      #print_h2 "Instance Usage", options
      print_stats_usage(stats)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def console(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '-n', '--node NODE_ID', "Scope console to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      build_common_options(opts, options, [:dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)

    begin
      instance = find_instance_by_name_or_id(args[0])
      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/terminal/#{instance['id']}"
      container_ids = instance['containers']
      if options[:node_id] && container_ids.include?(options[:node_id])
        link += "?containerId=#{options[:node_id]}"
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

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('-w','--wiki', "Open the wiki tab for this instance") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View an instance in a web browser" + "\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
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
      instance = find_instance_by_name_or_id(arg)
      return 1 if instance.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/instances/#{instance['id']}"
      if options[:link_tab]
        link << "#!#{options[:link_tab]}"
      end

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

  def logs(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on('--hosts HOSTS', String, "Filter logs to specific Host ID(s)") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--servers HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--vms HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
      # opts.on('--container CONTAINER', String, "Filter logs to specific Container ID(s)") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--nodes HOST', String, "alias for --containers") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on('--start TIMESTAMP','--start TIMESTAMP', "Start timestamp. Default is 30 days ago.") do |val|
        options[:start] = parse_time(val) #.utc.iso8601
      end
      opts.on('--end TIMESTAMP','--end TIMESTAMP', "End timestamp. Default is now.") do |val|
        options[:end] = parse_time(val) #.utc.iso8601
      end
      # opts.on('--interval TIME','--interval TIME', "Interval of time to include, in seconds. Default is 30 days ago.") do |val|
      #   options[:interval] = parse_time(val).utc.iso8601
      # end
      opts.on('--level VALUE', String, "Log Level. DEBUG,INFO,WARN,ERROR") do |val|
        params['level'] = params['level'] ? [params['level'], val].flatten : [val]
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
      instance = find_instance_by_name_or_id(args[0])
      container_ids = instance['containers']
      if options[:node_id]
        if container_ids.include?(options[:node_id])
          container_ids = [options[:node_id]]
        else
          print_red_alert "Instance does not include node #{options[:node_id]}"
          return 1
        end
      end
      params['level'] = params['level'].collect {|it| it.to_s.upcase }.join('|') if params['level'] # api works with INFO|WARN
      params.merge!(parse_list_options(options))
      params['query'] = params.delete('phrase') if params['phrase']
      params['order'] = params['direction'] unless params['direction'].nil? # old api version expects order instead of direction
      params['startMs'] = (options[:start].to_i * 1000) if options[:start]
      params['endMs'] = (options[:end].to_i * 1000) if options[:end]
      params['interval'] = options[:interval].to_s if options[:interval]
      @logs_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(container_ids, params)
        return
      end
      json_response = @logs_interface.container_logs(container_ids, params)
      render_result = json_response['logs'] ? render_with_format(json_response, options, 'logs') : render_with_format(json_response, options, 'data')
      return 0 if render_result
      
      title = "Instance Logs: #{instance['name']} (#{instance['instanceType'] ? instance['instanceType']['name'] : ''})"
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
      if params['servers']
        subtitles << "Servers: #{params['servers']}".strip
      end
      if params['containers']
        subtitles << "Containers: #{params['containers']}".strip
      end
      if params[:query]
        subtitles << "Search: #{params[:query]}".strip
      end
      if params['level']
        subtitles << "Level: #{params['level']}"
      end
      logs = json_response['data'] || json_response['logs']
      print_h1 title, subtitles, options
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

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('-a', '--all', "Display all details: containers|vms, and scaling." ) do
        options[:details] = true
        options[:include_containers] = true
        options[:include_scaling] = true
      end
      opts.on( nil, '--containers', "Display Instance Containers" ) do
        options[:include_containers] = true
      end
      opts.on( nil, '--nodes', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      # opts.add_hidden_option('--nodes')
      opts.on( nil, '--vms', "Alias for --containers" ) do
        options[:include_containers] = true
      end
      # opts.add_hidden_option('--vms')
      opts.on( nil, '--scaling', "Display Instance Scaling Settings" ) do
        options[:include_scaling] = true
      end
      opts.on( nil, '--costs', "Display Cost and Price" ) do
        options[:include_costs] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      # opts.on( nil, '--threshold', "Alias for --scaling" ) do
      #   options[:include_scaling] = true
      # end
      # opts.on( nil, '--lb', "Display Load Balancer Details" ) do
      #   options[:include_lb] = true
      # end
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about an instance.\n" + 
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
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
        @instances_interface.setopts(options)
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @instances_interface.dry.get(arg.to_i)
        else
          print_dry_run @instances_interface.dry.get({name:arg})
        end
        return
      end
      instance = find_instance_by_name_or_id(arg =~ /\A\d{1,}\Z/ ? arg.to_i : arg)
      @instances_interface.setopts(options)
      json_response = @instances_interface.get(instance['id'])
      if options[:quiet]
        return 0
      end
      if options[:json]
        puts as_json(json_response, options, "instance")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "instance")
        return 0
      end

      if options[:csv]
        puts records_as_csv([json_response['instance']], options)
        return 0
      end
      instance = json_response['instance']
      stats = instance['stats'] || json_response['stats'] || {}
      # load_balancers = json_response['loadBalancers'] || {}
      # metadata tags used to be returned as metadata and are now returned as tags
      # the problem is tags is what we used to call Labels (keywords)
      # the api will change to tags and labels, so handle the old format as long as metadata is returned.
      tags, labels = nil, nil
      if instance.key?('metadata')
        tags, labels = instance['metadata'], instance['tags']
      else
        tags, labels = instance['tags'], instance['labels']
      end
      # containers are fetched via separate api call
      containers = nil
      if options[:include_containers]
        containers = @instances_interface.containers(instance['id'])['containers']
      end

      # threshold is fetched via separate api call too
      instance_threshold = nil
      if options[:include_scaling]
        instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold']
      end

      # loadBalancers is returned via show
      # parse the current api format of loadBalancers.first.lbs.first
      current_instance_lb = nil
      if instance["currentLoadBalancerInstances"]
        current_instance_lb = instance['currentLoadBalancerInstances'][0]
      end

      # support old format
      if !current_instance_lb && json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      print_h1 "Instance Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : '' },
        "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
        "Type" => lambda {|it| it['instanceType']['name'] },
        "Layout" => lambda {|it| it['layout'] ? it['layout']['name'] : '' },
        "Version" => lambda {|it| it['instanceVersion'] },
        "Plan" => lambda {|it| it['plan'] ? it['plan']['name'] : '' },
        # "Cost" => lambda {|it| it['hourlyCost'] ? format_money(it['hourlyCost'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        # "Price" => lambda {|it| it['hourlyPrice'] ? format_money(it['hourlyPrice'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        "Environment" => 'instanceContext',
        "Labels" => lambda {|it| it['tags'] ? it['tags'].join(',') : '' },
        "Tags" => lambda {|it| tags ? tags.collect {|m| "#{m['name']}: #{m['value']}" }.join(', ') : '' },
        "Owner" => lambda {|it| 
          if it['owner']
            (it['owner']['username'] || it['owner']['id'])
          else
            it['createdBy'] ? (it['createdBy']['username'] || it['createdBy']['id']) : '' 
          end
        },
        #"Tenant" => lambda {|it| it['tenant'] ? it['tenant']['name'] : '' },
        "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        "Power Schedule" => lambda {|it| (it['powerSchedule'] && it['powerSchedule']['type']) ? it['powerSchedule']['type']['name'] : '' },
        "Last Deployment" => lambda {|it| (it['lastDeploy'] ? "#{it['lastDeploy']['deployment']['name']} #{it['lastDeploy']['deploymentVersion']['userVersion']} at #{format_local_dt it['lastDeploy']['deployDate']}" : nil) rescue "" },
        "Expire Date" => lambda {|it| it['expireDate'] ? format_local_dt(it['expireDate']) : '' },
        "Shutdown Date" => lambda {|it| it['shutdownDate'] ? format_local_dt(it['shutdownDate']) : '' },
        "Nodes" => lambda {|it| it['containers'] ? it['containers'].count : 0 },
        "Connection" => lambda {|it| format_instance_connection_string(it) },
        "Status" => lambda {|it| format_instance_status(it) }
      }
      description_cols.delete("Labels") if labels.nil? || labels.empty?
      description_cols.delete("Tags") if tags.nil? || tags.empty?
      description_cols.delete("Power Schedule") if instance['powerSchedule'].nil?
      description_cols.delete("Expire Date") if instance['expireDate'].nil?
      description_cols.delete("Shutdown Date") if instance['shutdownDate'].nil?
      description_cols["Removal Date"] = lambda {|it| format_local_dt(it['removalDate'])} if instance['status'] == 'pendingRemoval'
      description_cols.delete("Last Deployment") if instance['lastDeploy'].nil?
      #description_cols.delete("Environment") if instance['instanceContext'].nil?
      print_description_list(description_cols, instance)

      if instance['statusMessage']
        print_h2 "Status Message", options
        if instance['status'] == 'failed'
          print red, instance['statusMessage'], reset
        else
          print instance['statusMessage']
        end
        print "\n"
      end
      if instance['errorMessage']
        print_h2 "Error Message", options
        print red, instance['errorMessage'], reset, "\n"
      end
      if !instance['notes'].to_s.empty?
        print_h2 "Instance Notes", options
        print cyan, instance['notes'], reset, "\n"
      end
      wiki_page = instance['wikiPage']
      if wiki_page && wiki_page['content']
        print_h2 "Instance Wiki", options
        print cyan, truncate_string(wiki_page['content'], 100), reset, "\n"
        print "  Last updated by #{wiki_page['updatedBy'] ? wiki_page['updatedBy']['username'] : ''} on #{format_local_dt(wiki_page['lastUpdated'])}", reset, "\n"
      end
      if stats
        print_h2 "Instance Usage", options
        print_stats_usage(stats)
      end

      if options[:include_costs]
        print_h2 "Instance Cost"
        cost_columns = {
          "Cost" => lambda {|it| it['hourlyCost'] ? format_money(it['hourlyCost'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
          "Price" => lambda {|it| it['hourlyPrice'] ? format_money(it['hourlyPrice'], (it['currency'] || 'USD'), {sigdig:15}).to_s + ' per hour' : '' },
        }
        print_description_list(cost_columns, instance)
      end

      print reset, "\n"

      # if options[:include_lb]
      if current_instance_lb
        print_h2 "Load Balancer", options
        print cyan
        description_cols = {
          "LB ID" => lambda {|it| it['loadBalancer']['id'] },
          "Name" => lambda {|it| it['loadBalancer']['name'] },
          "Type" => lambda {|it| it['loadBalancer']['type'] ? it['loadBalancer']['type']['name'] : '' },
          "Host Name" => lambda {|it| it['vipHostname'] || instance['hostName'] },
          "Port" => lambda {|it| it['vipPort'] },
          "Protocol" => lambda {|it| it['vipProtocol'] || 'tcp' },
          "SSL Enabled" => lambda {|it| format_boolean(it['sslEnabled']) },
          "SSL Cert" => lambda {|it| (it['sslCert']) ? it['sslCert']['name'] : '' },
          "In" => lambda {|it| instance['currentLoadBalancerContainersIn'] },
          "Out" => lambda {|it| instance['currentLoadBalancerContainersOutrelo'] }
        }
        print_description_list(description_cols, current_instance_lb)
        print "\n", reset
      end
      # end

      if options[:include_containers]
        print_h2 "Instance Containers", options

        if containers.empty?
          print yellow,"No containers found for instance.",reset,"\n"
        else
          containers = containers.sort { |x,y| x['id'] <=> y['id'] }
          rows = containers.collect {|container| 
            stats = container['stats']
            cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
            memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
            storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
            if stats['maxMemory'] && stats['maxMemory'].to_i != 0
              memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(7, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
            end
            if stats['maxStorage'] && stats['maxStorage'].to_i != 0
              storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(7, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
            end
            row = {
              id: container['id'],
              status: format_container_status(container),
              name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
              type: container['containerType'] ? container['containerType']['name'] : '',
              host: container['server'] ? container['server']['name'] : '',
              cloud: container['cloud'] ? container['cloud']['name'] : '',
              location: format_container_connection_string(container),
              cpu: cpu_usage_str + cyan,
              memory: memory_usage_str + cyan, 
              storage: storage_usage_str + cyan
            }
            row
          }
          columns = [:id, :status, :name, :type, :cloud, :host, :location, :cpu, :memory, :storage]
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(rows, columns, options)
          print reset
          #print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
        end
        print reset,"\n"
      end

      if options[:include_scaling]
        print_h2 "Instance Scaling", options
        if instance_threshold.nil? || instance_threshold.empty?
          print cyan,"No scaling settings applied to this instance.",reset,"\n"
        else
          print cyan
          print_instance_threshold_description_list(instance_threshold)
          print reset,"\n"
        end
      end

      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(instance['status'])
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(arg, options)
        end
      end

      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def list_containers(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
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
      _list_containers(arg, options)
    end
  end

  def _list_containers(arg, options)
    params = {}
    begin
      instance = find_instance_by_name_or_id(arg)
      return 1 if instance.nil?
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.containers(instance['id'], params)
        return
      end
      json_response = @instances_interface.containers(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options, "containers")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "containers")
        return 0
      end

      if options[:csv]
        puts records_as_csv(json_response['containers'], options)
        return 0
      end
      

      containers = json_response['containers']
      containers = containers.sort { |x,y| x['id'] <=> y['id'] }
      title = "Instance Containers: #{instance['name']} (#{instance['instanceType']['name']})"
      print_h1 title, [], options
      if containers.empty?
        print cyan,"No containers found for instance.",reset,"\n"
      else

        rows = containers.collect {|container| 
          stats = container['stats']
          cpu_usage_str = !stats ? "" : generate_usage_bar((stats['usedCpu'] || stats['cpuUsage']).to_f, 100, {max_bars: 10})
          memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
          storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
          if stats['maxMemory'] && stats['maxMemory'].to_i != 0
            memory_usage_str = memory_usage_str + cyan + format_bytes_short(stats['usedMemory']).strip.rjust(7, ' ')  + " / " + format_bytes_short(stats['maxMemory']).strip
          end
          if stats['maxStorage'] && stats['maxStorage'].to_i != 0
            storage_usage_str = storage_usage_str + cyan + format_bytes_short(stats['usedStorage']).strip.rjust(7, ' ') + " / " + format_bytes_short(stats['maxStorage']).strip
          end
          row = {
            id: container['id'],
            status: format_container_status(container),
            name: container['server'] ? container['server']['name'] : '(no server)', # there is a server.displayName too?
            type: container['containerType'] ? container['containerType']['name'] : '',
            cloud: container['cloud'] ? container['cloud']['name'] : '',
            location: format_container_connection_string(container),
            cpu: cpu_usage_str + cyan,
            memory: memory_usage_str + cyan,
            storage: storage_usage_str + cyan
          }
          row
        }
        columns = [:id, :status, :name, :type, :cloud, :location, :cpu, :memory, :storage]
        # custom pretty table columns ...
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination({size: containers.size, total: containers.size}) # mock pagination
      end
      print reset,"\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backups(instance['id'], params)
        return
      end
      json_response = @instances_interface.backups(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      
      if json_response['backups'] && json_response['backups'][0] && json_response['backups'][0]['backupResults']
        # new format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options


        backup = json_response['backups'][0]

        description_cols = {
          "Backup ID" => lambda {|it| it['id'] },
          "Name" => lambda {|it| it['name'] },
          "Type" => lambda {|it| it['backupType'] ? (it['backupType']['name'] || it['backupType']['code']) : '' },
          "Storage" => lambda {|it| it['storageProvider'] ? it['storageProvider']['name'] : '' },
          "Schedule" => lambda {|it| it['cronDescription'] || it['cronExpression'] }
        }
        print_description_list(description_cols, backup)

        backup_results = backup ? backup['backupResults'] : nil
        backup_rows = backup_results.collect {|it| 
          status_str = it['status'].to_s.upcase
          # 'START_REQUESTED' //START_REQUESTED, IN_PROGRESS, CANCEL_REQUESTED, CANCELLED, SUCCEEDED, FAILED
          if status_str == 'SUCCEEDED'
            status_str = "#{green}#{status_str.upcase}#{cyan}"
          elsif status_str == 'FAILED'
            status_str = "#{red}#{status_str.upcase}#{cyan}"
          else
            status_str = "#{cyan}#{status_str.upcase}#{cyan}"
          end
          {id: it['id'], startDate: format_local_dt(it['dateCreated']), duration: format_duration_milliseconds(it['durationMillis']), 
            size: format_bytes(it['sizeInMb'], 'MB'), status: status_str }
        }
        print_h1 "Backup Results", [], options
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          {:startDate => {:display_name => "Started"} },
          :duration,
          :size,
          :status
        ]
        print reset, "\n"
      elsif json_response['backups'].size == 0
        # no backup configured
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        print "#{yellow}No backups configured#{reset}\n\n"
      else
        # old format
        print_h1 "Instance Backups: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        backups = json_response['backups']
        backup_rows = backups.collect {|r| 
          it = r['backup']
          {id: it['id'], name: it['name'], dateCreated: format_local_dt(it['dateCreated'])}
        }
        print cyan
        puts as_pretty_table backup_rows, [
          :id,
          :name,
          {:dateCreated => {:display_name => "Date Created"} }
        ]
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def clone(args)
    options = {:options => {}}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] -g GROUP")
      opts.on('--name VALUE', String, "Name") do |val|
        options[:options]['name'] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID for the new instance" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID for the new instance" ) do |val|
        options[:cloud] = val
      end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is on") do |val|
        options[:create_user] = !['false','off','0'].include?(val.to_s)
      end
      build_common_options(opts, options, [:options, :payload, :auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      options[:options] ||= {}
      options[:select_datastore] = true
      options[:name_required] = true

      # defaults derived from clone
      options[:default_name] = instance['name'] + '-clone' if instance['name']
      options[:default_group] = instance['group']['id'] if instance['group']
      options[:default_cloud] = instance['cloud']['name'] if instance['cloud']
      options[:default_plan] = instance['plan']['name'] if instance['plan']
      options[:default_resource_pool] = instance['config']['resourcePoolId'] if instance['config']
      options[:default_config] = instance['config']
      options[:default_security_group] = instance['config']['securityGroups'][0]['id'] if instance['config'] && (instance['config']['securityGroups'] || []).count > 0

      # immutable derived from clone
      options[:instance_type_code] = instance['instanceType']['code'] if instance['instanceType']
      options[:version] = instance['instanceVersion']
      options[:layout] = instance['layout']['id'] if instance['layout']

      # volume defaults
      options[:options]['volumes'] = instance['volumes']

      # network defaults
      options[:options]['networkInterfaces'] = instance['interfaces']

      # use the -g GROUP or active group by default
      #options[:options]['group'] ||= (options[:group] || @active_group_id)
      # support [new-name] 
      if args[1]
        options[:options]['name'] = args[1]
      end
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) || ['networkInterfaces'].include?(k)} : {}
      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        new_instance_payload = prompt_new_instance(options)

        # adjust for differences between new and clone payloads
        payload = new_instance_payload.delete('instance')
        payload.deep_merge!(new_instance_payload)
        payload['cloud'] = {'id' => payload.delete('zoneId')}
        payload['group'] = payload.delete('site')
      end
      unless passed_options.empty?
        passed_options.delete('cloud')
        passed_options.delete('group')
        payload.deep_merge!(passed_options)
      end
      
      # JD: this actually fixed a customer problem
      # It appears to be important to pass this... not sure if config.createUser is necessary...
      if options[:create_user].nil?
        options[:create_user] = true
      end
      if options[:create_user] != nil
        payload.deep_merge!({'createUser' => options[:create_user], 'config' =>{'createUser' => options[:create_user]}})
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to clone the instance #{instance['name']} as '#{payload['name']}'?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.clone(instance['id'], payload)
        return
      end
      json_response = @instances_interface.clone(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Cloning instance #{instance['name']} to '#{payload['name']}'"
      end
      return
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def envs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.get_envs(instance['id'])
        return
      end
      json_response = @instances_interface.get_envs(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      print_h1 "Instance Envs: #{instance['name']} (#{instance['instanceType']['name']})", [], options
      print cyan
      envs = json_response['envs'] || {}
      if json_response['readOnlyEnvs']
        envs += json_response['readOnlyEnvs'].map { |k,v| {:name => k, :value => k.downcase.include?("password") || v['masked'] ? "********" : v['value'], :export => true}}
      end
      columns = [:name, :value, :export]
      print_h2 "Imported Envs", options
      print as_pretty_table(envs, columns, options)
      print reset, "\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def setenv(args)
    options = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] VAR VALUE [-e]")
      opts.on( '-e', "Exportable" ) do |exportable|
        options[:export] = exportable
      end
      opts.on( '-M', "Masked" ) do |masked|
        options[:masked] = masked
      end
      build_common_options(opts, options, [:json, :dry_run, :remote, :quiet])
    end
    optparse.parse!(args)
    if args.count < 3
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      evar = {name: args[1], value: args[2], export: options[:export], masked: options[:masked]}
      payload = {envs: [evar]}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.create_env(instance['id'], payload)
        return
      end
      json_response = @instances_interface.create_env(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def delenv(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] VAR")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 2
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.del_env(instance['id'], args[1])
        return
      end
      json_response = @instances_interface.del_env(instance['id'], args[1])
      if options[:json]
        puts as_json(json_response, options)
        return
      end
      if !options[:quiet]
        envs([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    params = {'server' => true, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart(args)
    params = {'server' => true, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  # suspend should be server: false by default I guess..
  def suspend(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring')
      opts.on('--server [on|off]', String, "Suspend instance server. Default is off.") do |val|
        params['server'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Suspend an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to suspend #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.suspend(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.suspend(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Suspended instance #{instances[0]['name']}"
        else
          print_green_success "Suspended #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def eject(args)
    params = {'server' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Eject an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to eject #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.eject(instances.collect {|it| it['id'] }, params)
        return
      end
      json_response = @instances_interface.eject(instances.collect {|it| it['id'] }, params)
      if options[:json]
        puts as_json(json_response, options)
      elsif !options[:quiet]
        if instances.size == 1
          print_green_success "Ejected instance #{instances[0]['name']}"
        else
          print_green_success "Ejected #{instances.size} instances"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop_service(args)
    params = {'server' => false, 'muteMonitoring' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is off.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring') if opts.is_a?(Morpheus::Cli::OptionParser)
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Stop service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.stop(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.stop(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Stopping service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
      
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def start_service(args)
    params = {'server' => false}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Start service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.start(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.start(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Starting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def restart_service(args)
    params = {'server' => false, 'muteMonitoring' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on('--mute-monitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--muteMonitoring [on|off]', String, "Mute monitoring. Default is on.") do |val|
        params['muteMonitoring'] = val.nil? || val.to_s == 'on' || val.to_s == 'true'
      end
      opts.add_hidden_option('muteMonitoring')
      build_common_options(opts, options, [:auto_confirm, :quiet, :json, :dry_run, :remote])
      opts.footer = "Restart service on an instance.\n" +
                    "[instance] is required. This is the name or id of an instance. Supports 1-N [instance] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance_ids = parse_id_list(args)
      instances = []
      instance_ids.each do |instance_id|
        instance = find_instance_by_name_or_id(instance_id)
        return 1 if instance.nil?
        instances << instance
      end
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart service on #{instances.size == 1 ? 'instance' : (instances.size.to_s + ' instances')} #{anded_list(instances.collect {|it| it['name'] })}?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_h1 "DRY RUN", [], options
        instances.each do |instance|
          print_dry_run @instances_interface.dry.restart(instance['id'], params)
        end
        return 0
      end
      bad_responses = []
      instances.each do |instance|
        json_response = @instances_interface.restart(instance['id'], params)
        render_result = render_with_format(json_response, options)
        if render_result
          #return 0
        elsif !options[:quiet]
          print green, "Restarting service on instance #{instance['name']}", reset, "\n"
        end
        if json_response['success'] == false
          bad_responses << json_response
          if !options[:quiet]
            print_rest_errors(json_response)
          end
        end
      end
      if !bad_responses.empty?
        return 1
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def actions(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id or name list]")
      opts.footer = "List the actions available to specified instance(s)."
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} actions requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }
    begin
      # instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.available_actions(instance_ids)
        return 0
      end
      json_response = @instances_interface.available_actions(instance_ids)
      if options[:json]
        puts as_json(json_response, options)
      else
        title = "Instance Actions: #{anded_list(id_list)}"
        print_h1 title, [], options
        available_actions = json_response["actions"]
        if (available_actions && available_actions.size > 0)
          print as_pretty_table(available_actions, [:name, :code])
          print reset, "\n"
        else
          print "#{yellow}No available actions#{reset}\n\n"
        end
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def action(args)
    options = {}
    action_id = nil
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[id list] -a CODE")
      opts.on('-a', '--action CODE', "Instance Action CODE to execute") do |val|
        action_id = val.to_s
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Execute an action for one or many instances."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    instances = []
    id_list.each do |instance_id|
      instance = find_instance_by_name_or_id(instance_id)
      if instance.nil?
        # return 1
      else
        instances << instance
      end
    end
    if instances.size != id_list.size
      #puts_error "instances not found"
      return 1
    end
    instance_ids = instances.collect {|instance| instance["id"] }

    # figure out what action to run
    available_actions = @instances_interface.available_actions(instance_ids)["actions"]
    if available_actions.empty?
      if instance_ids.size > 1
        print_red_alert "The specified instances have no available actions in common."
      else
        print_red_alert "The specified instance has no available actions."
      end
      return 1
    end
    instance_action = nil
    if action_id.nil?
      available_actions_dropdown = available_actions.collect {|act| {'name' => act["name"], 'value' => act["code"]} } # already sorted
      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'code', 'type' => 'select', 'fieldLabel' => 'Instance Action', 'selectOptions' => available_actions_dropdown, 'required' => true, 'description' => 'Choose the instance action to execute'}], options[:options])
      action_id = v_prompt['code']
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s }
    else
      instance_action = available_actions.find {|act| act['code'].to_s == action_id.to_s || act['name'].to_s.downcase == action_id.to_s.downcase }
      action_id = instance_action["code"] if instance_action
    end
    if !instance_action
      # for testing bogus actions..
      # instance_action = {"id" => action_id, "name" => "Unknown"}
      raise_command_error "Instance Action '#{action_id}' not found."
    end

    action_display_name = "#{instance_action['name']} [#{instance_action['code']}]"    
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to perform action #{action_display_name} on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end

    # return run_command_for_each_arg(containers) do |arg|
    #   _action(arg, action_id, options)
    # end
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.action(instance_ids, action_id)
      return 0
    end
    json_response = @instances_interface.action(instance_ids, action_id)
    # just assume json_response["success"] == true,  it always is with 200 OK
    if options[:json]
      puts as_json(json_response, options)
    elsif !options[:quiet]
      # containers.each do |container|
      #   print green, "Action #{action_display_name} performed on container #{container['id']}", reset, "\n"
      # end
      print green, "Action #{action_display_name} performed on #{id_list.size == 1 ? 'instance' : 'instances'} #{anded_list(id_list)}", reset, "\n"
    end
    return 0
  end

  def resize(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])

      group_id = instance['group']['id']
      cloud_id = instance['cloud']['id']
      layout_id = instance['layout']['id']

      plan_id = instance['plan']['id']
      payload = {
        :instance => {:id => instance["id"]}
      }

      # avoid 500 error
      # payload[:servicePlanOptions] = {}

      puts "\nDue to limitations by most Guest Operating Systems, Disk sizes can only be expanded and not reduced.\nIf a smaller plan is selected, memory and CPU (if relevant) will be reduced but storage will not.\n\n"

      # prompt for service plan
      service_plans_json = @instances_interface.service_plans({zoneId: cloud_id, siteId: group_id, layoutId: layout_id})
      service_plans = service_plans_json["plans"]
      service_plans_dropdown = service_plans.collect {|sp| {'name' => sp["name"], 'value' => sp["id"]} } # already sorted
      service_plans_dropdown.each do |plan|
        if plan['value'] && plan['value'].to_i == plan_id.to_i
          plan['name'] = "#{plan['name']} (current)"
        end
      end
      plan_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => service_plans_dropdown, 'required' => true, 'description' => 'Choose the appropriately sized plan for this instance'}],options[:options])
      service_plan = service_plans.find {|sp| sp["id"] == plan_prompt['servicePlan'].to_i }
      new_plan_id = service_plan["id"]
      #payload[:servicePlan] = new_plan_id # ew, this api uses servicePlanId instead
      #payload[:servicePlanId] = new_plan_id
      payload[:instance][:plan] = {id: service_plan["id"]}

      volumes_response = @instances_interface.volumes(instance['id'])
      current_volumes = volumes_response['volumes'].sort {|x,y| x['displayOrder'] <=> y['displayOrder'] }

      # prompt for volumes
      volumes = prompt_resize_volumes(current_volumes, service_plan, options)
      if !volumes.empty?
        payload[:volumes] = volumes
      end

      # only amazon supports this option
      # for now, always do this
      payload[:deleteOriginalVolumes] = true
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.resize(instance['id'], payload)
        return
      end
      json_response = @instances_interface.resize(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        print_green_success "Resizing instance #{instance['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def backup(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to backup the instance '#{instance['name']}'?", options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.backup(instance['id'])
        return
      end
      json_response = @instances_interface.backup(instance['id'])
      if options[:json]
        puts as_json(json_response, options)
        return 0
      else
        bad_results = []
        if json_response['results']
          json_response['results'].each do |result_id, result|
            if result['success'] != true
              bad_results << result['msg'] || "Failed to create backup for instance #{result_id}"
            end
          end
        end
        if bad_results.empty?
          print_green_success "Backup initiated."
          return 0
        else
          print_red_alert bad_results.join("\n")
          return 1
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    query_params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on( '-B', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off. Applies to certain types only.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on('--releaseEIPs [on|off]', ['on','off'], "Release EIPs. Default is on. Applies to Amazon only.") do |val|
        query_params[:releaseEIPs] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts "\n#{optparse}\n\n"
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the instance '#{instance['name']}'?", options)
        exit 1
      end
      # JD: removeVolumes to maintain the old behavior with pre-3.5.2 appliances, remove me later
      if query_params[:preserveVolumes].nil?
        query_params[:removeVolumes] = 'on'
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.destroy(instance['id'],query_params)
        return
      end
      json_response = @instances_interface.destroy(instance['id'],query_params)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        print_green_success "Removing instance #{instance['name']}"
        #list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def cancel_removal(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.cancel_removal(instance['id'])
        return
      end
      json_response = @instances_interface.cancel_removal(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        get([instance['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_disable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_disable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_disable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.firewall_enable(instance['id'])
        return
      end
      json_response = @instances_interface.firewall_enable(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.security_groups(instance['id'])
        return
      end
      json_response = @instances_interface.security_groups(instance['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for Instance: #{instance['name']}", [], options
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      #print cyan, "Firewall Enabled=#{json_response['firewallEnabled']}\n\n"
      if securityGroups.empty?
        print yellow,"\n","No security groups currently applied.",reset,"\n"
      else
        print "\n"
        securityGroups.each do |securityGroup|
          print cyan, "=  #{securityGroup['id']} (#{securityGroup['name']}) - (#{securityGroup['description']})\n"
        end
        print "\n"
      end
      print reset, "\n"

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply_security_groups(args)
    options = {}
    security_group_ids = nil
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [-S] [-c]")
      opts.on( '-S', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        security_group_ids = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        security_group_ids = []
        clear_or_secgroups_specified = true
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    if !clear_or_secgroups_specified
      puts optparse
      exit
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      payload = {securityGroupIds: security_group_ids}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.apply_security_groups(instance['id'], payload)
        return
      end
      json_response = @instances_interface.apply_security_groups(instance['id'], payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      end
      if !options[:quiet]
        security_groups([args[0]] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def run_workflow(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [workflow] [options]")
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 2
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 2 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)
    instance = find_instance_by_name_or_id(args[0])
    workflow = find_workflow_by_name_or_id(args[1])
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
    params = {}
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # if params.empty? && !editable_options.empty?
    #   puts optparse
    #   option_lines = editable_options.collect {|it| "\t-O #{it['fieldContext'] ? (it['fieldContext'] + '.') : ''}#{it['fieldName']}=\"value\"" }.join("\n")
    #   puts "\nAvailable Options:\n#{option_lines}\n\n"
    #   exit 1
    # end

    workflow_payload = {taskSet: {"#{workflow['id']}" => params }}
    begin
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.workflow(instance['id'],workflow['id'], workflow_payload)
        return
      end
      json_response = @instances_interface.workflow(instance['id'],workflow['id'], workflow_payload)
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      else
        print_green_success "Running workflow #{workflow['name']} on instance #{instance['name']} ..."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def snapshots(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # no pagination yet
      # build_standard_list_options(opts, options)
      build_standard_get_options(opts, options)
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.snapshots(instance['id'], params)
        return
      end
      json_response = @instances_interface.snapshots(instance['id'], params)
      snapshots = json_response['snapshots']      
      render_response(json_response, options, 'snapshots') do
        print_h1 "Snapshots: #{instance['name']} (#{instance['instanceType']['name']})", [], options
        if snapshots.empty?
          print cyan,"No snapshots found",reset,"\n"
        else
          snapshot_column_definitions = {
            "ID" => lambda {|it| it['id'] },
            "Name" => lambda {|it| it['name'] },
            "Description" => lambda {|it| it['snapshotType'] ? (it['snapshotType']['name'] || it['snapshotType']['code']) : '' },
            "Date Created" => lambda {|it| format_local_dt(it['snapshotCreated']) },
            "Status" => lambda {|it| format_snapshot_status(it) }
          }
          print cyan
          print as_pretty_table(snapshots, snapshot_column_definitions.upcase_keys!, options)
          print_results_pagination({size: snapshots.size, total: snapshots.size})
        end
        print reset, "\n"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def import_snapshot(args)
    options = {}
    query_params = {}
    storage_provider_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      opts.on("--storage-provider ID", String, "Optional storage provider") do |val|
        storage_provider_id = val
      end
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to import a snapshot of the instance '#{instance['name']}'?", options)
        exit 1
      end

      payload = {}

      # Prompt for Storage Provider, use default value.
      begin
        options[:options] ||= {}
        options[:options]['storageProviderId'] = storage_provider_id if storage_provider_id
        storage_provider_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'storageProviderId', 'type' => 'select', 'fieldLabel' => 'Storage Provider', 'optionSource' => 'storageProviders', 'required' => false, 'description' => 'Select Storage Provider.'}], options[:options], @api_client, {})
        if !storage_provider_prompt['storageProviderId'].to_s.empty?
          payload['storageProviderId'] = storage_provider_prompt['storageProviderId']
        end
      rescue RestClient::Exception => e
        puts "Failed to load storage providers"
        #print_rest_exception(e, options)
        exit 1
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.import_snapshot(instance['id'], query_params, payload)
        return
      end
      json_response = @instances_interface.import_snapshot(instance['id'], query_params, payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Snapshot import initiated."
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def scaling(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Show scaling threshold information for an instance."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} scaling requires argument [id or name list]\n#{optparse}"
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _scaling(arg, options)
    end
  end

  def _scaling(arg, options)
    params = {}
    params.merge!(parse_list_options(options))
    instance = find_instance_by_name_or_id(arg)
    return 1 if instance.nil?
    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.threshold(instance['id'], params)
      return 0
    end
    json_response = @instances_interface.threshold(instance['id'], params)
    if options[:json]
      puts as_json(json_response, options, "instanceThreshold")
      return 0
    elsif options[:yaml]
      puts as_yaml(json_response, options, "instanceThreshold")
      return 0
    elsif options[:csv]
      puts records_as_csv([json_response['instanceThreshold']], options)
      return 0
    end

    instance_threshold = json_response['instanceThreshold']

    title = "Instance Scaling: [#{instance['id']}] #{instance['name']} (#{instance['instanceType']['name']})"
    print_h1 title, [], options
    if instance_threshold.empty?
      print cyan,"No scaling settings applied to this instance.",reset,"\n"
    else
      # print_h1 "Threshold Settings", [], options
      print cyan
      print_instance_threshold_description_list(instance_threshold)
    end
    print reset, "\n"
    return 0

  end

  def scaling_update(args)
    usage = "Usage: morpheus instances scaling-update [instance] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_option_type_options(opts, options, instance_scaling_option_types(nil))
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Update scaling threshold information for an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} scaling-update requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      instance_threshold = @instances_interface.threshold(instance['id'])['instanceThreshold'] || {}
      my_option_types = instance_scaling_option_types(instance)

      # preserve current values by setting the prompt options defaultValue attribute
      # note: checkbox type converts true,false to 'on','off'
      my_option_types.each do |opt|
        field_key = opt['fieldName'] # .sub('instanceThreshold.', '')
        if instance_threshold[field_key] != nil
          opt['defaultValue'] = instance_threshold[field_key]
        end
      end
      
      # params = Morpheus::Cli::OptionTypes.prompt(my_option_types, options[:options], @api_client, {})

      # ok, gotta split these inputs into sections with conditional logic
      params = {}

      option_types_group = my_option_types.select {|opt| ['autoUp', 'autoDown'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})

      option_types_group = my_option_types.select {|opt| ['zoneId'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['zoneId']
        if params['zoneId'] == '' || params['zoneId'] == 'null' || params['zoneId'].to_s == '0'
          params['zoneId'] = 0
        else
          params['zoneId'] = params['zoneId'].to_i
        end
      end

      option_types_group = my_option_types.select {|opt| ['minCount', 'maxCount'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})

      option_types_group = my_option_types.select {|opt| ['memoryEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['memoryEnabled'] == 'on' || params['memoryEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minMemory', 'maxMemory'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minMemory'] = nil
        params['maxMemory'] = nil
      end

      option_types_group = my_option_types.select {|opt| ['diskEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['diskEnabled'] == 'on' || params['diskEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minDisk', 'maxDisk'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minDisk'] = nil
        params['maxDisk'] = nil
      end

      option_types_group = my_option_types.select {|opt| ['cpuEnabled'].include?(opt['fieldName']) }
      params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      if params['cpuEnabled'] == 'on' || params['cpuEnabled'] == true
        option_types_group = my_option_types.select {|opt| ['minCpu', 'maxCpu'].include?(opt['fieldName']) }
        params.merge! Morpheus::Cli::OptionTypes.prompt(option_types_group, options[:options], @api_client, {})
      else
        params['minCpu'] = nil
        params['maxCpu'] = nil
      end

      # argh, convert on/off to true/false
      # this needs a global solution...
      params.each do |k,v|
        if v == 'on' || v == 'true' || v == 'yes'
          params[k] = true
        elsif v == 'off' || v == 'false' || v == 'no'
          params[k] = false
        end
      end      

      payload = {
        'instanceThreshold' => {}
      }
      payload['instanceThreshold'].merge!(params)

      # unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the scaling settings for instance '#{instance['name']}'?", options)
      #   return 9, "aborted command"
      # end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_threshold(instance['id'], payload)
        return
      end
      json_response = @instances_interface.update_threshold(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated scaling settings for instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def load_balancer_update(args)
    raise "Not Yet Implemented"
    usage = "Usage: morpheus instances lb-update [instance] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      #build_option_type_options(opts, options, instance_load_balancer_option_types(nil))
      build_common_options(opts, options, [:options, :json, :dry_run, :remote])
      opts.footer = "Assign a load balancer for an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-update requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      # refetch to get loadBalancers from show()
      json_response = @instances_interface.get(instance['id'])

      current_instance_lb = nil
      # refetch to get current load balancer info from show()
      json_response = @instances_interface.get(instance['id'])
      #load_balancers = @instances_interface.threshold(instance['id'])['loadBalancers'] || {}
      if json_response['loadBalancers'] && json_response['loadBalancers'][0] && json_response['loadBalancers'][0]['lbs'] && json_response['loadBalancers'][0]['lbs'][0]
        current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]
        #current_load_balancer = current_instance_lb['loadBalancer']
      end

      #my_option_types = instance_load_balancer_option_types(instance)

      # todo...

      # Host Name
      # Load Balancer
      # Protocol
      # Port
      # SSL Cert
      # Scheme

      current_instance_lb = json_response['loadBalancers'][0]['lbs'][0]

      params = {}
  
      payload = {
        'instance' => {},
        'networkLoadBalancer' => {}
      }

      cur_host_name = instance['hostName']
      #host_name = params = Morpheus::Cli::OptionTypes.prompt([{'fieldName'=>'hostName', 'label'=>'Host Name', 'defaultValue'=>cur_host_name}], options[:options], @api_client, {})
      payload['instance']['hostName'] = instance['hostName']

      #payload['loadBalancerId'] = params['loadBalancerId']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to update the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.update_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.update_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated scaling settings for instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def load_balancer_remove(args)
    usage = "Usage: morpheus instances lb-remove [instance] [options]"
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[instance]")
      build_option_type_options(opts, options, instance_scaling_option_types(nil))
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Remove a load balancer from an instance."
    end
    optparse.parse!(args)
    # if args.count < 1
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} lb-remove requires only one argument [id or name]\n#{optparse}"
      return 1
    end
    connect(options)

    begin

      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?

      # re-fetch via show() get loadBalancers
      json_response = @instances_interface.get(instance['id'])
      load_balancers = json_response['instance']['loadBalancers']

      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the load balancer for instance '#{instance['name']}'?", options)
        return 9, "aborted command"
      end
      
      # no options here, just send DELETE request
      payload = {}
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.remove_load_balancer(instance['id'], payload)
        return
      end
      json_response = @instances_interface.remove_load_balancer(instance['id'], payload)
      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Removed load balancer from instance #{instance['name']}"
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history(args)
    raw_args = args.dup
    options = {}
    #options[:show_output] = true
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance]")
      # opts.on( '-n', '--node NODE_ID', "Scope history to specific Container or VM" ) do |node_id|
      #   options[:node_id] = node_id.to_i
      # end
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on('--details', "Display more details: memory and storage usage used / max values." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      opts.on('--process-id ID', String, "Display details about a specfic process only." ) do |val|
        options[:process_id] = val
      end
      opts.on('--event-id ID', String, "Display details about a specfic process event only." ) do |val|
        options[:event_id] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes for a specific instance.\n" + 
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)

    # shortcut to other actions
    if options[:process_id]
      return history_details(raw_args)
    elsif options[:event_id]
      return history_event_details(raw_args)
    end

    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      # container_ids = instance['containers']
      # if options[:node_id] && container_ids.include?(options[:node_id])
      #   container_ids = [options[:node_id]]
      # end
      params = {}
      params.merge!(parse_list_options(options))
      # params['query'] = params.delete('phrase') if params['phrase']
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history(instance['id'], params)
        return
      end
      json_response = @instances_interface.history(instance['id'], params)
      if options[:json]
        puts as_json(json_response, options, "processes")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processes")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processes'], options)
        return 0
      else

        title = "Instance History: #{instance['name']}"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        if json_response['processes'].empty?
          print "#{cyan}No process history found.#{reset}\n\n"
        else
          history_records = []
          json_response["processes"].each do |process|
            row = {
              id: process['id'],
              eventId: nil,
              uniqueId: process['uniqueId'],
              name: process['displayName'],
              description: process['description'],
              processType: process['processType'] ? (process['processType']['name'] || process['processType']['code']) : process['processTypeName'],
              createdBy: process['createdBy'] ? (process['createdBy']['displayName'] || process['createdBy']['username']) : '',
              startDate: format_local_dt(process['startDate']),
              duration: format_process_duration(process),
              status: format_process_status(process),
              error: format_process_error(process, options[:details] ? nil : 20),
              output: format_process_output(process, options[:details] ? nil : 20)
            }
            history_records << row
            process_events = process['events'] || process['processEvents']
            if options[:show_events]
              if process_events
                process_events.each do |process_event|
                  event_row = {
                    id: process['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event, options[:details] ? nil : 20),
                    output: format_process_output(process_event, options[:details] ? nil : 20)
                  }
                  history_records << event_row
                end
              else
                
              end
            end
          end
          columns = [
            {:id => {:display_name => "PROCESS ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error
          ]
          if options[:show_events]
            columns.insert(1, {:eventId => {:display_name => "EVENT ID"} })
          end
          if options[:show_output]
            columns << :output
          end
          # custom pretty table columns ...
          if options[:include_fields]
            columns = options[:include_fields]
          end
          print cyan
          print as_pretty_table(history_records, columns, options)
          #print_results_pagination(json_response)
          print_results_pagination(json_response, {:label => "process", :n_label => "processes"})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_details(args)
    options = {}
    process_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [process-id]")
      opts.on('--process-id ID', String, "Display details about a specfic event." ) do |val|
        options[:process_id] = val
      end
      opts.add_hidden_option('process-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[process-id] is required. This is the id of the process."
    end
    optparse.parse!(args)
    if args.count == 2
      process_id = args[1]
    elsif args.count == 1 && options[:process_id]
      process_id = options[:process_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_details(instance['id'], process_id, params)
        return
      end
      json_response = @instances_interface.history_details(instance['id'], process_id, params)
      if options[:json]
        puts as_json(json_response, options, "process")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "process")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['process'], options)
        return 0
      else
        process = json_response["process"]
        title = "Instance History Details"
        subtitles = []
        subtitles << " Process ID: #{process_id}"
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_details(process)
  
        print_h2 "Process Events", options
        process_events = process['events'] || process['processEvents'] || []
        history_records = []
        if process_events.empty?
          puts "#{cyan}No events found.#{reset}"
        else      
          process_events.each do |process_event|
            event_row = {
                    id: process_event['id'],
                    eventId: process_event['id'],
                    uniqueId: process_event['uniqueId'],
                    name: process_event['displayName'], # blank like the UI
                    description: process_event['description'],
                    processType: process_event['processType'] ? (process_event['processType']['name'] || process_event['processType']['code']) : process['processTypeName'],
                    createdBy: process_event['createdBy'] ? (process_event['createdBy']['displayName'] || process_event['createdBy']['username']) : '',
                    startDate: format_local_dt(process_event['startDate']),
                    duration: format_process_duration(process_event),
                    status: format_process_status(process_event),
                    error: format_process_error(process_event),
                    output: format_process_output(process_event)
                  }
            history_records << event_row
          end
          columns = [
            {:id => {:display_name => "EVENT ID"} },
            :name, 
            :description, 
            {:processType => {:display_name => "PROCESS TYPE"} },
            {:createdBy => {:display_name => "CREATED BY"} },
            {:startDate => {:display_name => "START DATE"} },
            {:duration => {:display_name => "ETA/DURATION"} },
            :status, 
            :error,
            :output
          ]
          print cyan
          print as_pretty_table(history_records, columns, options)
          print_results_pagination({size: process_events.size, total: process_events.size})
          print reset, "\n"
          return 0
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def history_event_details(args)
    options = {}
    process_event_id = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [event-id]")
      opts.on('--event-id ID', String, "Display details about a specfic event." ) do |val|
        options[:event_id] = val
      end
      opts.add_hidden_option('event-id')
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display history details for a specific process event.\n" + 
                    "[instance] is required. This is the name or id of an instance.\n" +
                    "[event-id] is required. This is the id of the process event."
    end
    optparse.parse!(args)
    if args.count == 2
      process_event_id = args[1]
    elsif args.count == 1 && options[:event_id]
      process_event_id = options[:event_id]
    else
      puts_error optparse
      return 1
    end
    connect(options)
    begin
      instance = find_instance_by_name_or_id(args[0])
      params = {}
      params.merge!(parse_list_options(options))
      @instances_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @instances_interface.dry.history_event_details(instance['id'], process_event_id, params)
        return
      end
      json_response = @instances_interface.history_event_details(instance['id'], process_event_id, params)
      if options[:json]
        puts as_json(json_response, options, "processEvent")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "processEvent")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['processEvent'], options)
        return 0
      else
        process_event = json_response['processEvent'] || json_response['event']
        title = "Instance History Event"
        subtitles = []
        subtitles += parse_list_subtitles(options)
        print_h1 title, subtitles, options
        print_process_event_details(process_event, options)
        print reset, "\n"
        return 0
      end
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
      opts.footer = "Execute an arbitrary script or command on an instance." + "\n" +
                    "[id] is required. This is the id or name of an instance." + "\n" +
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
      instance = find_instance_by_name_or_id(args[0])
      return 1 if instance.nil?
      params['instanceId'] = instance['id']
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
      @execution_request_interface.setopts(options)
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

  def deploys(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[instance] [search]")
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List deployments for an instance.
[instance] is required. This is the name or id of an instance
[search] is optional. Filters on deployment version identifier
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    if args.count > 1
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    instance = find_instance_by_name_or_id(args[0])
    return 1 if instance.nil?
    # @deploy_interface.setopts(options)
    # if options[:dry_run]
    #   print_dry_run @deploy_interface.dry.list(instance['id'], params)
    #   return
    # end
    # json_response = @deploy_interface.list(instance['id'], params)

    @instances_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @instances_interface.dry.deploys(instance['id'], params)
      return
    end
    json_response = @instances_interface.deploys(instance['id'], params)

    app_deploys = json_response['appDeploys']
    render_response(json_response, options, 'appDeploys') do
      print_h1 "Instance Deploys", ["#{instance['name']}"] + parse_list_subtitles(options), options
      if app_deploys.empty?
        print cyan,"No deployments found.",reset,"\n"
      else
        print as_pretty_table(app_deploys, app_deploy_column_definitions.upcase_keys!, options)
        if json_response['meta']
          print_results_pagination(json_response)
        else
          print_results_pagination({size:app_deploys.size,total:app_deploys.size.to_i})
        end

      end
      print reset,"\n"
    end
    return 0
  end

private

  def find_zone_by_name_or_id(group_id, val)
    zone = nil
    if val.to_s =~ /\A\d{1,}\Z/
      clouds = get_available_clouds(group_id)
      zone = clouds.find {|it| it['id'] == val.to_i }
      if zone.nil?
        print_red_alert "Cloud not found by id #{val}"
        exit 1
      end
    else
      clouds = get_available_clouds(group_id)
      zone = clouds.find {|it| it['name'] == val.to_s }
      if zone.nil?
        print_red_alert "Cloud not found by name #{val}"
        exit 1
      end
    end
    return zone
  end

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
      print_red_alert "Host not found by name #{name}"
      exit 1
    elsif results['servers'].size > 1
      print_red_alert "Multiple hosts exist with the name #{name}. Try using id instead"
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

  def find_workflow_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_workflow_by_id(val)
    else
      return find_workflow_by_name(val)
    end
  end

  def find_workflow_by_id(id)
    begin
      json_response = @task_sets_interface.get(id.to_i)
      return json_response['taskSet']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Workflow not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_workflow_by_name(name)
    workflows = @task_sets_interface.list({name: name.to_s})['taskSets']
    if workflows.empty?
      print_red_alert "Workflow not found by name #{name}"
      return nil
    elsif workflows.size > 1
      print_red_alert "#{workflows.size} workflows by name #{name}"
      print_workflows_table(workflows, {color: red})
      print reset,"\n\n"
      return nil
    else
      return workflows[0]
    end
  end

  def instance_scaling_option_types(instance=nil)
    
    # Group
    group_id = nil
    if instance && instance['group']
      group_id = instance['group']['id']
    end

    available_clouds = group_id ? get_available_clouds(group_id) : []
    zone_dropdown = [{'name' => 'Use Scale Priority', 'value' => 0}] 
    zone_dropdown += available_clouds.collect {|cloud| {'name' => cloud['name'], 'value' => cloud['id']} }

    list = []
    list << {'fieldName' => 'autoUp', 'fieldLabel' => 'Auto Upscale', 'type' => 'checkbox', 'description' => 'Enable auto upscaling', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'autoDown', 'fieldLabel' => 'Auto Downscale', 'type' => 'checkbox', 'description' => 'Enable auto downscaling', 'required' => true, 'defaultValue' => false}
    
    list << {'fieldName' => 'zoneId', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => zone_dropdown, 'description' => "Choose a cloud to scale into.", 'placeHolder' => 'ID'}

    list << {'fieldName' => 'minCount', 'fieldLabel' => 'Min Count', 'type' => 'number', 'description' => 'Minimum number of nodes', 'placeHolder' => 'NUMBER'}
    list << {'fieldName' => 'maxCount', 'fieldLabel' => 'Max Count', 'type' => 'number', 'description' => 'Maximum number of nodes', 'placeHolder' => 'NUMBER'}
    

    list << {'fieldName' => 'memoryEnabled', 'fieldLabel' => 'Enable Memory Threshold', 'type' => 'checkbox', 'description' => 'Scale when memory thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minMemory', 'fieldLabel' => 'Min Memory', 'type' => 'number', 'description' => 'Minimum memory percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxMemory', 'fieldLabel' => 'Max Memory', 'type' => 'number', 'description' => 'Maximum memory percent (0-100)', 'placeHolder' => 'PERCENT'}

    list << {'fieldName' => 'diskEnabled', 'fieldLabel' => 'Enable Disk Threshold', 'type' => 'checkbox', 'description' => 'Scale when disk thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minDisk', 'fieldLabel' => 'Min Disk', 'type' => 'number', 'description' => 'Minimum storage percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxDisk', 'fieldLabel' => 'Max Disk', 'type' => 'number', 'description' => 'Maximum storage percent (0-100)', 'placeHolder' => 'PERCENT'}

    list << {'fieldName' => 'cpuEnabled', 'fieldLabel' => 'Enable CPU Threshold', 'type' => 'checkbox', 'description' => 'Scale when cpu thresholds are met.', 'required' => true, 'defaultValue' => false}
    list << {'fieldName' => 'minCpu', 'fieldLabel' => 'Min CPU', 'type' => 'number', 'description' => 'Minimum CPU percent (0-100)', 'placeHolder' => 'PERCENT'}
    list << {'fieldName' => 'maxCpu', 'fieldLabel' => 'Max CPU', 'type' => 'number', 'description' => 'Maximum CPU percent (0-100)', 'placeHolder' => 'PERCENT'}

    # list << {'fieldName' => 'iopsEnabled', 'fieldLabel' => 'Enable Iops Threshold', 'type' => 'checkbox', 'description' => 'Scale when iops thresholds are met.'}
    # list << {'fieldName' => 'minIops', 'fieldLabel' => 'Min Iops', 'type' => 'number', 'description' => 'Minimum iops'}
    # list << {'fieldName' => 'maxIops', 'fieldLabel' => 'Max Iops', 'type' => 'number', 'description' => 'Maximum iops'}

    # list << {'fieldName' => 'networkEnabled', 'fieldLabel' => 'Enable Iops Threshold', 'type' => 'checkbox', 'description' => 'Scale when network thresholds are met.'}
    # list << {'fieldName' => 'minNetwork', 'fieldLabel' => 'Min Network', 'type' => 'number', 'description' => 'Minimum networking'}

    # list << {'fieldName' => 'comment', 'fieldLabel' => 'Comment', 'type' => 'text', 'description' => 'Comment on these scaling settings.'}

    list
  end

  def instance_load_balancer_option_types(instance=nil)
    list = []
    list << {'fieldContext' => 'instance', 'fieldName' => 'hostName', 'fieldLabel' => 'Host Name', 'type' => 'checkbox', 'description' => 'Enable auto upscaling', 'required' => true, 'defaultValue' => instance ? instance['hostName'] : nil}
    list << {'fieldName' => 'proxyProtocol', 'fieldLabel' => 'Protocol', 'type' => 'checkbox', 'description' => 'Enable auto downscaling', 'required' => true, 'defaultValue' => false}
    list
  end

  def print_instance_threshold_description_list(instance_threshold)
    description_cols = {
      # "Instance" => lambda {|it| "#{instance['id']} - #{instance['name']}" },
      "Auto Upscale" => lambda {|it| format_boolean(it['autoUp']) },
      "Auto Downscale" => lambda {|it| format_boolean(it['autoDown']) },
      "Cloud" => lambda {|it| it['zoneId'] ? "#{it['zoneId']}" : 'Use Scale Priority' },
      "Min Count" => lambda {|it| it['minCount'] },
      "Max Count" => lambda {|it| it['maxCount'] },
      "Memory Enabled" => lambda {|it| format_boolean(it['memoryEnabled']) },
      "Min Memory" => lambda {|it| it['memoryEnabled'] ? (it['minMemory'] ? "#{it['minMemory']}%" : '') : '' },
      "Max Memory" => lambda {|it| it['memoryEnabled'] ? (it['maxMemory'] ? "#{it['maxMemory']}%" : '') : '' },
      "Disk Enabled" => lambda {|it| format_boolean(it['diskEnabled']) },
      "Min Disk" => lambda {|it| it['diskEnabled'] ? (it['minDisk'] ? "#{it['minDisk']}%" : '') : '' },
      "Max Disk" => lambda {|it| it['diskEnabled'] ? (it['maxDisk'] ? "#{it['maxDisk']}%" : '') : '' },
      "CPU Enabled" => lambda {|it| format_boolean(it['cpuEnabled']) },
      "Min CPU" => lambda {|it| it['cpuEnabled'] ? (it['minCpu'] ? "#{it['minCpu']}%" : '') : '' },
      "Max CPU" => lambda {|it| it['cpuEnabled'] ? (it['maxCpu'] ? "#{it['maxCpu']}%" : '') : '' },
      # "Iops Enabled" => lambda {|it| format_boolean(it['iopsEnabled']) },
      # "Min Iops" => lambda {|it| it['minIops'] },
      # "Max Iops" => lambda {|it| it['maxDisk'] },
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
    print_description_list(description_cols, instance_threshold)
  end

  def print_process_details(process)
    description_cols = {
      "Process ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['displayName'] },
      "Description" => lambda {|it| it['description'] },
      "Process Type" => lambda {|it| it['processType'] ? (it['processType']['name'] || it['processType']['code']) : it['processTypeName'] },
      "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['displayName'] || it['createdBy']['username']) : '' },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Duration" => lambda {|it| format_process_duration(it) },
      "Status" => lambda {|it| format_process_status(it) },
      # "# Events" => lambda {|it| (it['events'] || []).size() },
    }
    print_description_list(description_cols, process)

    if process['error']
      print_h2 "Error", options
      print reset
      #puts format_process_error(process_event)
      puts process['error'].to_s.strip
    end

    if process['output']
      print_h2 "Output", options
      print reset
      #puts format_process_error(process_event)
      puts process['output'].to_s.strip
    end
  end

  def print_process_event_details(process_event, options={})
    # process_event =~ process
    description_cols = {
      "Process ID" => lambda {|it| it['processId'] },
      "Event ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['displayName'] },
      "Description" => lambda {|it| it['description'] },
      "Process Type" => lambda {|it| it['processType'] ? (it['processType']['name'] || it['processType']['code']) : it['processTypeName'] },
      "Created By" => lambda {|it| it['createdBy'] ? (it['createdBy']['displayName'] || it['createdBy']['username']) : '' },
      "Start Date" => lambda {|it| format_local_dt(it['startDate']) },
      "End Date" => lambda {|it| format_local_dt(it['endDate']) },
      "Duration" => lambda {|it| format_process_duration(it) },
      "Status" => lambda {|it| format_process_status(it) },
    }
    print_description_list(description_cols, process_event)

    if process_event['error']
      print_h2 "Error", options
      print reset
      #puts format_process_error(process_event)
      puts process_event['error'].to_s.strip
    end

    if process_event['output']
      print_h2 "Output", options
      print reset
      #puts format_process_error(process_event)
      puts process_event['output'].to_s.strip
    end
  end
  
  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end

  def app_deploy_column_definitions
    {
      "ID" => 'id',
      "Deployment" => lambda {|it| it['deployment']['name'] rescue '' },
      "Version" => lambda {|it| (it['deploymentVersion']['userVersion'] || it['deploymentVersion']['version']) rescue '' },
      "Deploy Date" => lambda {|it| format_local_dt(it['deployDate']) },
      "Status" => lambda {|it| format_app_deploy_status(it['status']) },
    }
  end

end
