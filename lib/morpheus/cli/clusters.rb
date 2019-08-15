# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
#require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::Clusters
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper
  include Morpheus::Cli::AccountsHelper

  register_subcommands :list, :count, :get, :view, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clusters_interface = @api_client.clusters
    @groups_interface = @api_client.groups
    @compute_type_layouts_interface = @api_client.library_compute_type_layouts
    @security_groups_interface = @api_client.security_groups
    #@security_group_rules_interface = @api_client.security_group_rules
    @cloud_resource_pools_interface = @api_client.cloud_resource_pools
    @clouds_interface = @api_client.clouds
    @servers_interface = @api_client.servers
    @server_types_interface = @api_client.server_types
    @options_interface = @api_client.options
    @active_group_id = Morpheus::Cli::Groups.active_group
    @provision_types_interface = @api_client.provision_types
    @user_groups_interface = @api_client.user_groups
    #@active_security_group = ::Morpheus::Cli::SecurityGroups.load_security_group_file
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List clusters."
    end
    optparse.parse!(args)
    if args.count != 0
      raise_command_error "wrong number of arguments, expected 0 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.list(params)
        return
      end
      json_response = @clusters_interface.list(params)
      
      render_result = render_with_format(json_response, options, 'clusters')
      return 0 if render_result

      title = "Morpheus Clusters"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles

      clusters = json_response['clusters']
      
      if clusters.empty?
        print yellow,"No clusters found.",reset,"\n"
      else
        print_clusters_table(clusters, options)
      end
      print reset,"\n"
      return 0
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
      opts.footer = "Get the number of clusters."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.get(params)
        return
      end
      json_response = @clusters_interface.get(params)
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
      opts.banner = subcommand_usage("[id]")
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_status] ||= "provisioned,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "Get details about a cluster."
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
      @clusters_interface.setopts(options)

      if options[:dry_run]
        if arg.to_s =~ /\A\d{1,}\Z/
          print_dry_run @clusters_interface.dry.get(arg.to_i)
        else
          print_dry_run @clusters_interface.dry.list({name:arg})
        end
        return 0
      end
      cluster = find_cluster_by_name_or_id(arg)
      return 1 if cluster.nil?
      json_response = nil
      if arg.to_s =~ /\A\d{1,}\Z/
        json_response = {'cluster' => cluster}  # skip redundant request
      else
        json_response = @clusters_interface.get(cluster['id'])
      end

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
        return
      end

      cluster = json_response['cluster']
      worker_stats = cluster['workerStats']
      clusterType = find_cluster_type_by_id(cluster['type']['id'])

      print_h1 "Morpheus Cluster"
      print cyan
      description_cols = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda { |it| it['type']['name'] },
          "Code" => 'code',
          "Group" => lambda { |it| it['site']['name'] },
          "Cloud" => lambda { |it| it['zone']['name'] },
          "Location" => lambda { |it| it['location'] },
          "Visibility" => lambda { |it| it['visibility'].to_s.capitalize },
          #"Groups" => lambda {|it| it['groups'].collect {|g| g.instance_of?(Hash) ? g['name'] : g.to_s }.join(', ') },
          #"Owner" => lambda {|it| it['owner'].instance_of?(Hash) ? it['owner']['name'] : it['ownerId'] },
          #"Tenant" => lambda {|it| it['account'].instance_of?(Hash) ? it['account']['name'] : it['accountId'] },
          "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
          "Enabled" => lambda { |it| format_boolean(it['enabled']) },
          "Status" => lambda { |it| format_cluster_status(it) }
      }
      print_description_list(description_cols, cluster)

      print_h2 "Cluster Details"
      print cyan

      print "Namespaces: #{cluster['namespaceCount']}".center(20) if cluster['namespaces']
      print "Masters: #{cluster['masterCount']}".center(20) if clusterType['hasMasters']
      print "Workers: #{cluster['workerCount']}".center(20) if clusterType['hasWorkers']
      print "Volumes: #{cluster['volumeCount']}".center(20) if cluster['volumes']
      print "Containers: #{cluster['containerCount']}".center(20) if cluster['containers']
      print "Services: #{cluster['serviceCount']}".center(20) if cluster['services']
      print "Jobs: #{cluster['jobCount']}".center(20) if cluster['jobs']
      print "Pods: #{cluster['podCount']}".center(20) if cluster['pods']
      print "Deployments: #{cluster['deploymentCount']}".center(20) if cluster['deployments']
      print "\n"

      if worker_stats
        print_h2 "Worker Usage"
        print cyan
        # print "CPU Usage: #{worker_stats['cpuUsage']}".center(20)
        # print "Memory: #{worker_stats['usedMemory']}".center(20)
        # print "Storage: #{worker_stats['usedStorage']}".center(20)
        print_stats_usage(worker_stats)
        print "\n"
      end
      
      print reset,"\n"


      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(cluster['status'])
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

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[cluster]")
      opts.on('-w','--wiki', "Open the wiki tab for this cluster") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View a cluster in a web browser" + "\n" +
                    "[cluster] is required. This is the name or id of a cluster. Supports 1-N [cluster] arguments."
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
      cluster = find_cluster_by_name_or_id(arg)
      return 1 if cluster.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/infrastructure/clusters/#{cluster['id']}"
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

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name] [description]")
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      opts.on( '--resource-name NAME', "Resource Name" ) do |val|
        options[:resourceName] = val.to_s
      end
      opts.on( '--resource-description DESCRIPTION', "Resource Description" ) do |val|
        options[:resourceDescription] = val
      end
      opts.on('--tags LIST', String, "Tags") do |val|
        options[:tags] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Cloud Name or ID" ) do |val|
        options[:cloud] = val
      end
      opts.on( '-t', '--cluster-type TYPE', "Cluster Type Name or ID" ) do |val|
        options[:clusterType] = val
      end
      opts.on( '-l', '--layout LAYOUT', "Layout Name or ID" ) do |val|
        options[:layout] = val
      end
      opts.on( '--resource-pool ID', String, "ID of the Resource Pool for Amazon VPC and Azure Resource Group" ) do |val|
        options[:resourcePool] = val
      end
      opts.on( '-p', '--plan PLAN', "Service Plan") do |val|
        options[:servicePlan] = val
      end
      opts.on('--max-memory VALUE', String, "Maximum Memory (MB)") do |val|
        options[:maxMemory] = val
      end
      opts.on('--cpu-count VALUE', String, "CPU Count") do |val|
        options[:cpuCount]
      end
      opts.on('--core-count VALUE', String, "Core Count") do |val|
        options[:coreCount]
      end
      opts.on('--cores-per-socket VALUE', String, "Cores Per Socket") do |val|
        options[:coresPerSocket]
      end
      opts.on('--volumes JSON', String, "Volumes Config JSON") do |val|
        begin
          volumes = JSON.parse(val.to_s)
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse volumes JSON"
          exit 1
        end
        options[:volumes] = volumes.kind_of?(Array) ? volumes : [volumes]
      end
      opts.on('--volumes-file FILE', String, "Volumes Config from a local JSON or YAML file") do |val|
        config_file = File.expand_path(val)
        if !File.exists?(config_file) || !File.file?(config_file)
          print_red_alert "Specified volumes file not found: #{config_file}"
          exit 1
        end
        if config_file =~ /\.ya?ml\Z/
          begin
            volumes = YAML.load_file(config_file)
          rescue YAML::ParseError
            print_red_alert "Unable to parse volumes YAML from: #{config_file}"
            exit 1
          end
        else
          volumes =
          begin
            volumes = JSON.parse(File.read(config_file))
          rescue JSON::ParserError
            print_red_alert "Unable to parse volumes JSON from: #{config_file}"
            exit 1
          end
        end
        options[:volumes] = volumes.kind_of?(Array) ? volumes : [volumes]
      end
      opts.on('--config-file FILE', String, "Instance Config from a local JSON or YAML file") do |val|
        options['configFile'] = val.to_s
      end
      opts.on('--network-interfaces JSON', String, "Network Interfaces Config JSON") do |val|
        begin
          networkInterfaces = JSON.parse(val.to_s)
        rescue JSON::ParserError => e
          print_red_alert "Unable to parse volumes JSON"
          exit 1
        end
        options[:networkInterfaces] = networkInterfaces.kind_of?(Array) ? networkInterfaces : [networkInterfaces]
      end
      opts.on('--network-interfaces-file FILE', String, "Network Interfaces Config from a local JSON or YAML file") do |val|
        config_file = File.expand_path(val)
        if !File.exists?(config_file) || !File.file?(config_file)
          print_red_alert "Specified network interfaces file not found: #{config_file}"
          exit 1
        end
        if config_file =~ /\.ya?ml\Z/
          begin
            volumes = YAML.load_file(config_file)
          rescue YAML::ParseError
            print_red_alert "Unable to parse volumes YAML from: #{config_file}"
            exit 1
          end
        else
          volumes =
              begin
                volumes = JSON.parse(File.read(config_file))
              rescue JSON::ParserError
                print_red_alert "Unable to parse volumes JSON from: #{config_file}"
                exit 1
              end
        end
        options[:networkInterfaces] = volumes.kind_of?(Array) ? networkInterfaces : [networkInterfaces]
      end
      opts.on('--security-groups LIST', Array, "Security Groups") do |list|
        options[:securityGroups] = list
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options[:visibility] = val
      end
      opts.on("--create-user on|off", String, "User Config: Create Your User. Default is off") do |val|
        options[:createUser] = ['true','on','1'].include?(val.to_s)
      end
      opts.on("--user-group USERGROUP", String, "User Config: User Group") do |val|
        options[:userGroup] = val
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options[:visibility] = val
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end

    optparse.parse!(args)
    connect(options)

    begin
      payload = nil
      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['cluster'] ||= {}
          payload['cluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end
      else
        payload = {"server" => {}, "config" => {}}

        # Cluster Type
        cluster_type_id = nil
        cluster_type = options[:clusterType] ? find_cluster_type_by_name_or_id(options[:clusterType]) : nil

        if cluster_type
          cluster_type_id = cluster_type['id']
        else
          available_cluster_types = cluster_types_for_dropdown

          if available_cluster_types.empty?
            print_red_alert "A cluster type is required"
            exit 1
          elsif available_cluster_types.count > 1 && !options[:no_prompt]
            cluster_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'clusterType', 'type' => 'select', 'fieldLabel' => 'Cluster Type', 'selectOptions' => cluster_types_for_dropdown, 'required' => true, 'description' => 'Select Cluster Type.'}],options[:options],@api_client,{})['clusterType']
          else
            cluster_type_code = available_cluster_types.first['code']
          end
          cluster_type = get_cluster_types.find { |ct| ct['code'] == cluster_type_code }
        end

        payload['type'] = cluster_type['code'] # {'id' => cluster_type['id']}

        # Cluster Name
        if args.empty? && options[:no_prompt]
          print_red_alert "No cluster name provided"
          exit 1
        elsif !args.empty?
          payload['name'] = args[0]
        else
          existing_cluster_names = @clusters_interface.list()['clusters'].collect { |cluster| cluster['name'] }
          while payload['name'].empty?
            name = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Cluster Name', 'required' => true, 'description' => 'Cluster Name.'}],options[:options],@api_client,{})['name']

            if existing_cluster_names.include?(name)
              print_red_alert "Name must be unique, #{name} already exists"
            else
              payload['name'] = name
            end
          end
        end

        # Cluster Description
        if !args.empty? && args.count > 1
          payload['description'] = args[1]
        elsif options[:description]
          payload['description'] = options[:description]
        elsif !options[:no_prompt]
          payload['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'desc', 'type' => 'text', 'fieldLabel' => 'Cluster Description', 'required' => false, 'description' => 'Cluster Description.'}],options[:options],@api_client,{})['desc']
        end

        # Resource Name
        resourceName = options[:resourceName]

        if !resourceName
          if options[:no_prompt]
            print_red_alert "No resource name provided"
            exit 1
          else
            resourceName = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Resource Name', 'required' => true, 'description' => 'Resource Name.'}],options[:options],@api_client,{})['name']
          end
        end

        payload['server']['name'] = resourceName

        # Resource Description
        resourceDescription = options[:resourceDescription]

        if !resourceDescription && !options[:no_prompt]
          resourceDescription = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'desc', 'type' => 'text', 'fieldLabel' => 'Resource Description', 'required' => false, 'description' => 'Resource Description.'}],options[:options],@api_client,{})['desc']
        end

        payload['server']['description'] = resourceDescription if resourceDescription

        tags = options[:tags]

        if !tags && !options[:no_prompt]
          tags = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tags', 'type' => 'text', 'fieldLabel' => 'Resource Tags', 'required' => false, 'description' => 'Resource Tags.'}],options[:options],@api_client,{})['tags']
        end

        payload['server']['tags'] = tags if tags

        # Group / Site
        group_id = nil
        group = options[:group] ? find_group_by_name_or_id_for_provisioning(options[:group]) : nil

        if group
          group_id = group["id"]
        else
          if @active_group_id
            group_id = @active_group_id
          else
            available_groups = get_available_groups

            if available_groups.empty?
              print_red_alert "No available groups"
              exit 1
            elsif available_groups.count > 1 && !options[:no_prompt]
              group_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'type' => 'select', 'fieldLabel' => 'Group', 'selectOptions' => available_groups, 'required' => true, 'description' => 'Select Group.'}],options[:options],@api_client,{})['group']
            else
              group_id = available_groups.first['id']
            end
          end
        end

        group = @groups_interface.get(group_id)['group']
        payload['group'] = {'id' => group['id']}

        # Cloud / Zone
        cloud_id = nil
        cloud = options[:cloud] ? find_cloud_by_name_or_id_for_provisioning(group['id'], options[:cloud]) : nil
        if cloud
          # load full cloud
          cloud = @clouds_interface.get(cloud['id'])['zone']
          cloud_id = cloud['id']
        else
          available_clouds = get_available_clouds(group['id'])

          if available_clouds.empty?
            print_red_alert "Group #{group['name']} has no available clouds"
            exit 1
          elsif available_clouds.count > 1 && !options[:no_prompt]
            cloud_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'type' => 'select', 'fieldLabel' => 'Cloud', 'selectOptions' => available_clouds, 'required' => true, 'description' => 'Select Cloud.'}],options[:options],@api_client,{groupId: group_id})['cloud']
          else
            cloud_id = available_clouds.first["id"]
          end
          cloud = @clouds_interface.get(cloud_id)['zone']
        end

        cloud['zoneType'] = @clouds_interface.cloud_type(cloud['zoneType']['id'])['zoneType']
        payload['cloud'] = {'id' => cloud['id']}

        # Layout
        layout_id = nil
        layout = options[:layout] ? find_layout_by_name_or_id(options[:layout]) : nil

        if layout
          layout_id = layout['id']
        else
          available_layouts = layouts_for_dropdown(cloud['id'], cluster_type['id'])

          if !available_layouts.empty?
            if available_layouts.count > 1 && !options[:no_prompt]
              layout_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'layout', 'type' => 'select', 'fieldLabel' => 'Layout', 'selectOptions' => available_layouts, 'required' => true, 'description' => 'Select Layout.'}],options[:options],@api_client,{})['layout']
            else
              layout_id = available_layouts.first['id']
            end
            layout = find_layout_by_name_or_id(layout_id)['layout']
          end
        end

        payload['layout'] = layout['code']

        # Plan
        service_plan_id = nil
        service_plan = options[:servicePlan] ? find_service_plan_by_name_or_id(options[:servicePlan]) : nil
        provision_type = (layout && layout['provisionType'] ? layout['provisionType'] : nil) || get_provision_type_for_cloud(cloud)

        if service_plan
          service_plan_id = service_plan['id']
        else
          available_service_plans = service_plans_for_dropdown(cloud['id'], provision_type['id'])

          if available_service_plans.empty?
            print_red_alert "Cloud #{cloud['name']} has no available plans"
            exit 1
          elsif available_service_plans.count > 1 && !options[:no_prompt]
            service_plan_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'servicePlan', 'type' => 'select', 'fieldLabel' => 'Plan', 'selectOptions' => available_service_plans, 'required' => true, 'description' => 'Select Plan.'}],options[:options],@api_client,{})['servicePlan']
          else
            service_plan_id = available_service_plans.first['id']
          end
          service_plan = find_service_plan_by_id(service_plan_id)
        end

        # service plan options
        if service_plan
          payload['server']['plan'] = {'code' => service_plan['code'], 'options' => {}}

          # custom max memory
          if service_plan['customMaxMemory']
            if !options[:maxMemory]
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'maxMemory', 'type' => 'number', 'fieldLabel' => 'Max Memory (MB)', 'required' => false, 'description' => 'This will override any memory requirement set on the virtual image', 'defaultValue' => service_plan['maxMemory'] ? service_plan['maxMemory'] / (1024 * 1024) : 10 }], options[:options])
              payload['server']['plan']['options']['maxMemory'] = v_prompt['maxMemory'] * 1024 * 1024 if v_prompt['maxMemory']
            else
              payload['server']['plan']['options']['maxMemory'] = options[:maxMemory]
            end
          end

          # custom cores: max cpu, max cores, cores per socket
          if service_plan['customCores']
            if !options[:cpuCount]
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cpuCount', 'type' => 'number', 'fieldLabel' => 'CPU Count', 'required' => false, 'description' => 'Set CPU Count', 'defaultValue' => service_plan['maxCpu'] ? service_plan['maxCpu'] : 1 }], options[:options])
              payload['server']['plan']['options']['cpuCount'] = v_prompt['cpuCount'] if v_prompt['cpuCount']
            else
              payload['server']['plan']['options']['cpuCount']
            end
            if !options[:coreCount]
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'coreCount', 'type' => 'number', 'fieldLabel' => 'Core Count', 'required' => false, 'description' => 'Set Core Count', 'defaultValue' => service_plan['maxCores'] ? service_plan['maxCores'] : 1 }], options[:options])
              payload['server']['plan']['options']['coreCount'] = v_prompt['coreCount'] if v_prompt['coreCount']
            end
            if !options[:coresPerSocket] && service_plan['coresPerSocket']
              v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'coresPerSocket', 'type' => 'number', 'fieldLabel' => 'Cores Per Socket', 'required' => false, 'description' => 'Set Core Per Socket', 'defaultValue' => service_plan['coresPerSocket']}], options[:options])
              payload['server']['plan']['options']['coresPerSocket'] = v_prompt['coresPerSocket'] if v_prompt['coresPerSocket']
            end
          end
        end

        # Controller type
        server_types = @server_types_interface.list({max:1, computeTypeId: cluster_type['controllerTypes'].first['id'], zoneTypeId: cloud['zoneType']['id'], useZoneProvisionTypes: true})['serverTypes']
        controller_provision_type = nil
        resource_pool = nil

        if !server_types.empty?
          controller_type = server_types.first
          controller_provision_type = controller_type['provisionType'] ? (@provision_types_interface.get(controller_type['provisionType']['id'])['provisionType'] rescue nil) : nil

          if controller_provision_type && controller_provision_type['hasZonePools']
            # Resource pool
            if ! ['resourcePoolId', 'resourceGroup', 'vpc'].find { |it| cloud['config'][it] && cloud['config'][it].length > 0 }
              resource_pool_id = nil
              resource_pool = options[:resourcePool] ? find_cloud_resource_pool_by_name_or_id(cloud['id'], options[:resourcePool]) : nil

              if resource_pool
                resource_pool_id = resource_pool['id']
              else
                resource_pool_options = @options_interface.options_for_source('zonePools', {groupId: group['id'], zoneId: cloud['id'], planId: (service_plan['id'] rescue nil)})['data']

                if resource_pool_options.empty?
                  print_red_alert "Cloud #{cloud['name']} has no available resource pools"
                  exit 1
                elsif resource_pool_options.count > 1 && !options[:no_prompt]
                  resource_pool_id = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'resourcePool', 'type' => 'select', 'fieldLabel' => 'Resource Pool', 'selectOptions' => resource_pool_options, 'required' => true, 'skipSingleOption' => true, 'description' => 'Select resource pool.'}],options[:options],api_client, {})['resourcePool']
                else
                  resource_pool_id = resource_pool_options.first['id']
                end
                resource_pool = @cloud_resource_pools_interface.get(cloud['id'], resource_pool_id)['resourcePool']
              end
              payload['config']['resourcePool'] = resource_pool['externalId']
            end
          end
        end

        # Multi-disk / prompt for volumes
        volumes = options[:volumes] || prompt_volumes(controller_provision_type, options, @api_client, {})

        if !volumes.empty?
          payload['volumes'] = volumes
        end

        # Networks
        # NOTE: You must choose subnets in the same availability zone
        if controller_provision_type['hasNetworks'] && cloud['zoneType']['code'] != 'esxi'
          payload['networkInterfaces'] = options[:networkInterfaces] || prompt_network_interfaces(cloud['id'], provision_type['id'], options)
        end

        # Security Groups
        if cloud['zoneType']['hasSecurityGroups'] && ['amazon', 'rds'].include?(provision_type['code']) && resource_pool
          # Require at least 1 security group
          security_groups = options[:securityGroups] || []

          if security_groups.empty?
            available_security_groups = @api_client.options.options_for_source('zoneSecurityGroup', {zoneId: cloud['id'], poolId: resource_pool['id']})['data']

            if available_security_groups.empty?
              #print_red_alert "Cloud #{cloud['name']} has no available plans"
              #exit 1
            elsif available_security_groups.count > 1 && !options[:no_prompt]
              while !available_security_groups.empty? && (security_groups.empty? || Morpheus::Cli::OptionTypes.confirm("Add security group?", {:default => false}))
                security_group = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'securityGroup', 'type' => 'select', 'fieldLabel' => 'Security Group', 'selectOptions' => available_security_groups, 'required' => true, 'description' => 'Select Security Group.'}], options[:options], @api_client, {})['securityGroup']
                security_groups << security_group
                available_security_groups.reject! { |sg| sg['value'] == security_group }
              end
            else
              security_groups << available_security_groups[0]
            end
          end
          payload['securityGroups'] = security_groups
        end

        # Visibility
        payload['visibility'] = options[:visibility] || (Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'defaultValue' => 'private', 'required' => true, 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}]}], options[:options], @api_client, {})['visibility'])

        # Options / Custom Config
        option_type_list = ((controller_type['optionTypes'].reject { |type| !type['enabled'] || type['fieldComponent'] } rescue []) + layout['optionTypes'] +
          (cluster_type['optionTypes'].reject { |type| !type['enabled'] || !type['creatable'] || type['fieldComponent'] } rescue [])).sort { |type| type['displayOrder'] }

        # remove volume options if volumes were configured
        if !payload['volumes'].empty?
          option_type_list = reject_volume_option_types(option_type_list)
        end
        # remove networkId option if networks were configured above
        if !payload['networkInterfaces'].empty?
          option_type_list = reject_networking_option_types(option_type_list)
        end

        payload.deep_merge!(Morpheus::Cli::OptionTypes.prompt(option_type_list, options[:options], @api_client, {zoneId: cloud['id']}))

        # Create User
        if !options[:createUser].nil?
          payload['config']['createUser'] = options[:createUser]
        elsif !options[:no_prompt]
          current_user['windowsUsername'] || current_user['linuxUsername']
          payload['config']['createUser'] = (current_user['windowsUsername'] || current_user['linuxUsername']) && Morpheus::Cli::OptionTypes.confirm("Create Your User?", {:default => false})
        end

        # User Groups
        userGroup = options[:userGroup] ? find_user_group_by_name_or_id(current_user, options[:userGroup]) : nil

        if userGroup
          payload['server']['userGroup'] = userGroup
        elsif !options[:no_prompt]
          userGroupId = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'userGroupId', 'fieldLabel' => 'User Group', 'type' => 'select', 'required' => false, 'optionSource' => 'userGroups'}], options[:options], @api_client, {})['userGroupId']

          if userGroupId
            payload['server']['userGroup'] = {'id' => userGroupId}
          end
        end

        # Host / Domain
        payload['server']['networkDomain'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkDomain', 'fieldLabel' => 'Network Domain', 'type' => 'select', 'required' => false, 'optionSource' => 'networkDomains'}], options[:options], @api_client, {})['networkDomain']
        payload['server']['hostname'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hostname', 'fieldLabel' => 'Hostname', 'type' => 'text', 'description' => 'Hostname'}], options[:options], @api_client)['hostname']

        # Envelop it
        payload = {'cluster' => payload}
      end
      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.create(payload)
        return
      end
      json_response = @clusters_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["cluster"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage( "[name] --name --description --active")
      opts.on("--name NAME", String, "Updates Cluster Name") do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Updates Cluster Description") do |val|
        options[:description] = val.to_s
      end
      opts.on('--active [on|off]', String, "Can be used to enable / disable the cluster. Default is on") do |val|
        options[:active] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == '1' || val.to_s == ''
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is provisioned,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
    end

    optparse.parse!(args)
    connect(options)

    begin
      payload = nil
      cluster = nil

      if options[:payload]
        payload = options[:payload]
        # support -O OPTION switch on top of --payload
        if options[:options]
          payload['cluster'] ||= {}
          payload['cluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) })
        end

        if !payload['cluster'].empty?
          cluster = find_cluster_by_name_or_id(payload['cluster']['id'] || payload['cluster']['name'])
        end
      else
        if !args.empty?
          cluster = find_cluster_by_name_or_id(args[0])

          if !cluster
            print_red_alert "Cluster not found"
            exit 1
          end
        elsif !options[:no_prompt]
          available_clusters = @clusters_interface.list['clusters'].collect { |it| {'id' => it['id'], 'name' => it['name'], 'value' => it['id']} }

          if available_clusters.count
            existing_cluster_names = available_clusters.collect {|it| it['name']}
            cluster = find_cluster_by_id(Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'clusterId', 'type' => 'select', 'fieldLabel' => 'Cluster', 'selectOptions' => available_clusters.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Cluster.'}], options[:options], @api_client, {})['clusterId'])
          end
        else
          print_red_alert "No cluster specified"
          exit 1
        end

        cluster_payload = {}
        cluster_payload['name'] = options[:name] if !options[:name].empty?
        cluster_payload['description'] = options[:description] if !options[:description].empty?
        cluster_payload['enabled'] = options[:active] if !options[:active].nil?
        payload = {"cluster" => cluster_payload}
      end

      if !cluster
        print_red_alert "No clusters available for update"
        exit 1
      end

      if !['name', 'description', 'enabled'].find {|field| payload['cluster'] && !payload['cluster'][field].nil? && payload['cluster'][field] != cluster[field] ? field : nil}
        print_green_success "Nothing to update"
        exit 1
      end

      print_red_alert payload

      @clusters_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clusters_interface.dry.update(cluster['id'], payload)
        return
      end
      json_response = @clusters_interface.update(cluster['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif json_response['success']
        get_args = [json_response["cluster"]["id"]] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      else
        print_rest_errors(json_response, options)
      end
    end
  end

  private

  def print_clusters_table(clusters, opts={})
    table_color = opts[:color] || cyan
    rows = clusters.collect do |cluster|
      {
          id: cluster['id'],
          name: cluster['name'],
          type: (cluster['type']['name'] rescue ''),
          layout: (cluster['layout']['name'] rescue ''),
          workers: cluster['workerCount'],
          cloud: (cluster['zone']['name'] rescue ''),
          status: format_cluster_status(cluster)
      }
    end
    columns = [
        :id, :name, :type, :layout, :workers, :cloud, :status
    ]
    print as_pretty_table(rows, columns, opts)
  end

  def format_cluster_status(cluster, return_color=cyan)
    out = ""
    status_string = cluster['status']
    if cluster['enabled'] == false || status_string == 'error'
      out << "#{red}DISABLED#{return_color}"
    elsif status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing' || status_string.include?('provision')
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{cluster['statusMessage'] ? "#{return_color} - #{cluster['statusMessage']}" : ''}#{return_color}"
    end
    out
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

  def find_cluster_type_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cluster_type_by_id(val) : find_cluster_type_by_name(val)
  end

  def find_cluster_type_by_id(id)
    get_cluster_types.find { |it| it['id'] == id }
  end

  def find_cluster_type_by_name(name)
    get_cluster_types.find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase }
  end

  def cluster_types_for_dropdown
    get_cluster_types.collect {|it| {'id' => it['id'], 'name' => it['name'], 'code' => it['code'], 'value' => it['code']} }
  end

  def get_cluster_types(refresh=false)
    if !@cluster_types || refresh
      @cluster_types = @clusters_interface.cluster_types()['clusterTypes']
    end
    @cluster_types
  end

  def find_layout_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_layout_by_id(val) : find_layout_by_name(val)
  end

  def find_layout_by_id(id)
    @compute_type_layouts_interface.get(id)
  end

  def find_layout_by_name(name)
    @compute_type_layouts_interface.list({phrase:name}).find { it['name'].downcase == name.downcase || it['code'].downcase == name.downcase }
  end

  def layouts_for_dropdown(zone_id, group_type_id)
    @compute_type_layouts_interface.list({zoneId: zone_id, groupTypeId: group_type_id})["layouts"].collect { |it| {'id' => it['id'], 'name' => it['name'], 'value' => it['id'], 'code' => it['code']} }
  end

  def find_service_plan_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_service_plan_by_id(val) : find_service_plan_by_name(val)
  end

  def find_service_plan_by_id(id)
    @servers_interface.service_plan(id)['servicePlan'] rescue nil
  end

  def find_service_plan_by_name(name)
    @servers_interface.service_plan({phrase: name})['servicePlans'].find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase } rescue nil
  end

  def find_security_group_by_name(val)
    @security_groups_interface.list({phrase: val})['securityGroups'][0] rescue nil
  end

  def find_cloud_resource_pool_by_name_or_id(cloud_id, val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cloud_resource_pool_by_id(cloud_id, val) : find_cloud_resource_pool_by_name(cloud_id, val)
  end

  def find_cloud_resource_pool_by_name(cloud_id, name)
    get_cloud_resource_pools(cloud_id).find { |it| it['name'].downcase == name.downcase } rescue nil
  end

  def find_cloud_resource_pool_by_id(cloud_id, id)
    get_cloud_resource_pools(cloud_id).find { |it| it['id'] == id } rescue nil
  end

  def get_cloud_resource_pools(cloud_id, refresh=false)
    if !@cloud_resource_pools || refresh
      @cloud_resource_pools = @cloud_resource_pools_interface.list(cloud_id)['resourcePools']
    end
    @cloud_resource_pools
  end

  def service_plans_for_dropdown(zone_id, provision_type_id)
    @servers_interface.service_plans({zoneId: zone_id, provisionTypeId: provision_type_id})['plans'] rescue []
  end

  def get_cloud_type(id)
    @clouds_interface.cloud_type(id)['zoneType']
  end

  def get_provision_type_for_cloud(cloud)
    @clouds_interface.cloud_type(cloud['zoneTypeId'])['zoneType']['provisionTypes'].first rescue nil
  end

  def current_user(refresh=false)
    if !@current_user || refresh
      load_whoami
    end
    @current_user
  end
end
