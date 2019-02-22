# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/accounts_helper'
require 'morpheus/cli/mixins/provisioning_helper'
require 'morpheus/cli/mixins/processes_helper'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::ProcessesHelper
  set_command_name :apps
  set_command_description "View and manage apps."
  register_subcommands :list, :get, :add, :update, :remove, :add_instance, :remove_instance, :logs, :firewall_disable, :firewall_enable, :security_groups, :apply_security_groups, :history
  register_subcommands :stop, :start, :restart
  #register_subcommands :validate # add --validate instead
  alias_subcommand :details, :get
  set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @users_interface = @api_client.users
    @apps_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).apps
    @blueprints_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).blueprints
    @instance_types_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instance_types
    @instances_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).instances
    @options_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).options
    @groups_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).groups
    @logs_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).logs
    @processes_interface = @api_client.processes
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '--created-by USER', "Created By User Username or ID" ) do |val|
        options[:created_by] = val
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List apps."
    end
    optparse.parse!(args)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} list expects 0 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      account = nil
      if options[:created_by]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:created_by])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(params)
        return
      end

      json_response = @apps_interface.get(params)
      if options[:json]
        puts as_json(json_response, options, "apps")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "apps")
        return 0
      elsif options[:csv]
        puts records_as_csv(json_response['apps'], options)
        return 0
      end
      
      apps = json_response['apps']
      title = "Morpheus Apps"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles, options
      if apps.empty?
        print cyan,"No apps found.",reset,"\n"
      else
        print_apps_table(apps, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      #build_option_type_options(opts, options, add_app_option_types(false))
      # these come from build_options_types
      opts.on( '-b', '--blueprint BLUEPRINT', "Blueprint Name or ID. The default value is 'existing' which means no blueprint, for creating a blank app and adding existing instances." ) do |val|
        options[:blueprint] = val
      end
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '-c', '--cloud CLOUD', "Default Cloud Name or ID." ) do |val|
        options[:cloud] = val
      end
      opts.on( '--name VALUE', String, "Name" ) do |val|
        options[:name] = val
      end
      opts.on( '--description VALUE', String, "Description" ) do |val|
        options[:description] = val
      end
      opts.on( '-e', '--environment VALUE', "Environment Name" ) do |val|
        options[:environment] = val.to_s == 'null' ? nil : val
      end
      # config is being deprecated in favor of the standard --payload options
      # opts.add_hidden_option(['config', 'config-dir', 'config-file', 'config-yaml'])
      opts.on('--validate','--validate', "Validate Only. Validates the configuration and skips creating it.") do
        options[:validate_only] = true
      end
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? 5 : val.to_f
      end
      build_common_options(opts, options, [:options, :payload, :json, :yaml, :dry_run, :quiet])
      opts.footer = "Create a new app.\n" +
                    "[name] is required. This is the name of the new app. It may also be passed as --name or inside your config."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add expects 0-1 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    # allow name as first argument
    if args[0] # && !options[:name]
      options[:name] = args[0]
    end
    connect(options)
    begin
      options[:options] ||= {}
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = {}
      if options[:payload]
        # payload is from parsed json|yaml files or arguments.
        payload = options[:payload]
        # merge -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?
        # support some options on top of --payload
        [:name, :description, :environment].each do |k|
          if options.key?(k)
            payload[k.to_s] = options[k]
          end
        end
      else
        # prompt for payload
        payload = {}
        # merge -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?

        # this could have some special -O context, like -O tier.Web.0.instance.name
        # tier_config_options = payload.delete('tier')

        # Blueprint
        blueprint_id = 'existing'
        blueprint = nil
        if options[:blueprint]
          blueprint_id = options[:blueprint]
          options[:options]['blueprint'] = options[:blueprint]
        end
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'blueprint', 'fieldLabel' => 'Blueprint', 'type' => 'select', 'selectOptions' => get_available_blueprints(), 'required' => true, 'defaultValue' => 'existing', 'description' => "The blueprint to use. The default value is 'existing' which means no template, for creating a blank app and adding existing instances."}], options[:options])
        blueprint_id = v_prompt['blueprint']
        
        if blueprint_id.to_s.empty? || blueprint_id == 'existing'
          blueprint = {"id" => "existing", "name" => "Existing Instances", "value" => "existing", "type" => "morpheus"}
        else
          blueprint = find_blueprint_by_name_or_id(blueprint_id)
          if blueprint.nil?
            print_red_alert "Blueprint not found by name or id '#{blueprint_id}'"
            return 1
          end
        end
        
        payload['templateId'] = blueprint['id'] # for pre-3.6 api
        payload['blueprintId'] = blueprint['id']
        payload['blueprintName'] = blueprint['name'] #for future api plz

        # Name
        options[:options]['name'] = options[:name] if options.key?(:name)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'}], options[:options])
        payload['name'] = v_prompt['name']
        

        # Description
        options[:options]['description'] = options[:description] if options.key?(:description)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false}], options[:options])
        payload['description'] = v_prompt['description']
        

        # Group
        group_id = nil
        options[:options]['group'] = options[:group] if options.key?(:group)
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => get_available_groups(), 'required' => true, 'defaultValue' => @active_group_id}], options[:options])
        group_id = v_prompt['group']
        
        group = find_group_by_name_or_id_for_provisioning(group_id)
        return 1 if group.nil?
        payload['group'] = {'id' => group['id'], 'name' => group['name']}

        # Default Cloud
        cloud_id = nil
        scoped_available_clouds = get_available_clouds(group['id'])
        if options[:cloud]
          cloud_id = options[:cloud]
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'fieldLabel' => 'Default Cloud', 'type' => 'select', 'selectOptions' => scoped_available_clouds}], options[:options])
          cloud_id = v_prompt['cloud'] unless v_prompt['cloud'].to_s.empty?
        end
        if cloud_id
          cloud = find_cloud_by_name_or_id_for_provisioning(group['id'], cloud_id)
          #payload['cloud'] = {'id' => cloud['id'], 'name' => cloud['name']}
        end
        
        # Environment
        if options[:environment]
          payload['environment'] = options[:environment]
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'text', 'required' => false}], options[:options])
          payload['environment'] = v_prompt['environment'] unless v_prompt['environment'].to_s.empty?
        end
        # payload['appContext'] = payload['environment'] if payload['environment']


        if !payload['tiers']
          if payload['blueprintId'] != 'existing'
            
            # fetch the app template
            blueprint = find_blueprint_by_name_or_id(payload['blueprintId'])
            return 1 if blueprint.nil?
            
            unless options[:quiet]
              print cyan, "Configuring app with blueprint id: #{blueprint['id']}, name: #{blueprint['name']}, type: #{blueprint['type']}\n"
            end
            
            blueprint_type = blueprint['type'] || 'morpheus'
            if blueprint_type == 'morpheus'
              # configure each tier and instance in the blueprint
              # tiers are a map, heh, sort them by tierIndex
              tiers = blueprint["config"]["tiers"] ? blueprint["config"]["tiers"] : (blueprint["tiers"] || {})
              sorted_tiers = tiers.collect {|k,v| [k,v] }.sort {|a,b| a[1]['tierIndex'] <=> b[1]['tierIndex'] }
              sorted_tiers.each do |tier_obj|
                tier_name = tier_obj[0]
                tier_config = tier_obj[1]
                payload['tiers'] ||= {}
                payload['tiers'][tier_name] ||= tier_config.clone
                # remove instances, they will be iterated over and merged back in
                tier_instances = payload['tiers'][tier_name].delete("instances")
                # remove other blank stuff
                if payload['tiers'][tier_name]['linkedTiers'] && payload['tiers'][tier_name]['linkedTiers'].empty?
                  payload['tiers'][tier_name].delete('linkedTiers')
                end
                # remove extra instance options at tierName.index, probabl need a namespace here like tier.TierName.index
                tier_extra_options = {}
                if payload[tier_name]
                  tier_extra_options = payload.delete(tier_name)
                end
                tier_instance_types = tier_instances ? tier_instances.collect {|it| (it['instance'] && it['instance']['type']) ? it['instance']['type'].to_s : 'unknown'}.compact : []
                unless options[:quiet]
                  # print cyan, "Configuring Tier: #{tier_name} (#{tier_instance_types.empty? ? 'empty' : tier_instance_types.join(', ')})", "\n"
                  print cyan, "Configuring tier #{tier_name}", reset, "\n"
                end
                # todo: also prompt for tier settings here, like linkedTiers: []
                if tier_instances
                  tier_instances = tier_config['instances'] || []
                  tier_instances.each_with_index do |instance_config, instance_index|
                    instance_type_code = instance_config['type']
                    if instance_config['instance'] && instance_config['instance']['type']
                      instance_type_code = instance_config['instance']['type']
                    end
                    if instance_type_code.nil?
                      print_red_alert "Unable to determine instance type for tier: #{tier_name} index: #{instance_index}"
                      return 1
                    else
                      unless options[:quiet]
                        print cyan, "Configuring #{instance_type_code} instance #{tier_name}.#{instance_index}", reset, "\n"
                      end

                      # Cloud
                      cloud_id = nil
                      v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => scoped_available_clouds, 'defaultValue' => cloud ? cloud['name'] : nil}], options[:options])
                      cloud_id = v_prompt['cloud'] unless v_prompt['cloud'].to_s.empty?
                      if cloud_id
                        # cloud = find_cloud_by_name_or_id_for_provisioning(group['id'], cloud_id)
                        cloud = scoped_available_clouds.find {|it| it['name'] == cloud_id.to_s } || scoped_available_clouds.find {|it| it['id'].to_s == cloud_id.to_s }
                        return 1 if cloud.nil?
                      else
                        # prompt still happens inside get_scoped_instance_config
                      end
                      
                      
                      # prompt for the cloud for this instance
                      # the cloud is part of finding the scoped config in the blueprint
                      scoped_instance_config = get_scoped_instance_config(instance_config.clone, payload['environment'], group ? group['name'] : nil, cloud ? cloud['name'] : nil)

                      # now configure an instance like normal, use the config as default options with :always_prompt
                      instance_prompt_options = {}
                      instance_prompt_options[:group] = group ? group['id'] : nil
                      instance_prompt_options[:cloud] = cloud ? cloud['name'] : nil
                      instance_prompt_options[:default_cloud] = cloud ? cloud['name'] : nil
                      instance_prompt_options[:no_prompt] = options[:no_prompt]
                      instance_prompt_options[:always_prompt] = options[:no_prompt] != true # options[:always_prompt]
                      instance_prompt_options[:options] = scoped_instance_config # meh, actually need to make these default values instead..
                      instance_prompt_options[:options][:always_prompt] = instance_prompt_options[:no_prompt] != true
                      instance_prompt_options[:options][:no_prompt] = instance_prompt_options[:no_prompt]

                      # also allow arbritrary options passed as tierName.instanceIndex like Web.0.instance.layout.id=75
                      instance_extra_options = {}
                      if tier_extra_options && tier_extra_options[instance_index.to_s]
                        instance_extra_options = tier_extra_options[instance_index.to_s]
                      end
                      instance_prompt_options[:options].deep_merge!(instance_extra_options)

                      #instance_prompt_options[:name_required] = true
                      instance_prompt_options[:instance_type_code] = instance_type_code
                      # todo: an effort to render more useful help eg.  -O Web.0.instance.name
                      instance_prompt_options[:extra_field_context] = "#{tier_name}.#{instance_index}" 
                      # this provisioning helper method handles all (most) of the parsing and prompting
                      instance_config_payload = prompt_new_instance(instance_prompt_options)
                      
                      # strip all empty string and nil
                      instance_config_payload.deep_compact!
                      # use the blueprint config as the base
                      final_config = scoped_instance_config.clone
                      # merge the prompted values
                      final_config.deep_merge!(instance_config_payload)
                      final_config.delete('environments')
                      final_config.delete('groups')
                      final_config.delete('clouds')
                      # add config to payload
                      payload['tiers'][tier_name]['instances'] ||= []
                      payload['tiers'][tier_name]['instances'] << final_config
                    end
                  end
                else
                  puts yellow, "Tier '#{tier_name}' is empty", reset
                end
              end
            elsif blueprint_type == 'terraform'
              # prompt for Terraform config
              # todo
            elsif blueprint_type == 'arm'
              # prompt for ARM config
              # todo
            elsif blueprint_type == 'cloudFormation'
              # prompt for cloudFormation config
              # todo
            else
              print yellow, "Unknown template type: #{template_type})", "\n"
            end
          end
        end
      end

      @apps_interface.setopts(options)

      # Validate Only
      if options[:validate_only] == true
        # Validate Only Dry run 
        if options[:dry_run]
          if options[:json]
            puts as_json(payload, options)
          elsif options[:yaml]
            puts as_yaml(payload, options)
          else
            print_dry_run @apps_interface.dry.validate(payload)
          end
          return 0
        end
        json_response = @apps_interface.validate(payload)

        if options[:json]
          puts as_json(json_response, options)
        else
          if !options[:quiet]
            if json_response['success'] == true
              print_green_success "New app '#{payload['name']}' validation passed. #{json_response['msg']}".strip
            else
              print_red_alert "New app '#{payload['name']}' validation failed. #{json_response['msg']}".strip
              if json_response['errors'] && json_response['errors']['instances']
                json_response['errors']['instances'].each do |error_obj|
                  tier_name = error_obj['tier']
                  instance_index = error_obj['index']
                  instance_errors = error_obj['instanceErrors']
                  print_error red, "#{tier_name} : #{instance_index}", "\n", reset
                  if instance_errors
                    instance_errors.each do |err_key, err_msg|
                      print_error red, " * #{err_key} : #{err_msg}", "\n", reset
                    end
                  end
                end
              else
                # a default way to print errors
                (json_response['errors'] || []).each do |error_key, error_msg|
                  print_error " * #{error_key} : #{error_msg}", "\n"
                end
              end
            end
          end
        end
        if json_response['success'] == true
          return 0
        else
          return 1
        end
      end

      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.create(payload)
        return 0
      end

      json_response = @apps_interface.create(payload)

      if options[:json]
        puts as_json(json_response, options)
        print "\n"
      elsif !options[:quiet]
        app = json_response["app"]
        print_green_success "Added app #{app['name']}"
        # add existing instances to blank app now?
        if !options[:no_prompt] && !payload['tiers'] && payload['id'] == 'existing'
          if ::Morpheus::Cli::OptionTypes::confirm("Would you like to add an instance now?", options.merge({default: false}))
            add_instance([app['id']])
            while ::Morpheus::Cli::OptionTypes::confirm("Add another instance?", options.merge({default: false})) do
              add_instance([app['id']])
            end
          end
        end
        # print details
        if options[:refresh_interval]
          get([app['id'], '--refresh', options[:refresh_interval].to_s])
        else
          get([app['id']])
        end
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
      opts.banner = subcommand_usage("[app]")
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is 5 seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :outfile, :dry_run, :remote])
      opts.footer = "Get details about an app.\n" +
                    "[app] is required. This is the name or id of an app. Supports 1-N [app] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} get expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end

    connect(options)

    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, options)
    end
    
  end

  def _get(arg, options={})
    begin
      app = find_app_by_name_or_id(arg)
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.get(app['id'])
        return
      end
      json_response = @apps_interface.get(app['id'])

      render_result = render_with_format(json_response, options, 'blueprint')
      return 0 if render_result

      app = json_response['app']
      app_tiers = app['appTiers']
      print_h1 "App Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : '' },
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : it['siteId'] },
        "Account" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Tiers" => lambda {|it| 
          # it['instanceCount']
          tiers = []
          app_tiers = it['appTiers'] || []
          app_tiers.each do |app_tier|
            tiers << app_tier['tier']
          end
          "#{tiers.collect {|it| it.is_a?(Hash) ? it['name'] : it }.join(',')}"
        },
        "Instances" => lambda {|it| 
          # it['instanceCount']
          instances = []
          app_tiers = it['appTiers'] || []
          app_tiers.each do |app_tier|
            instances += (app_tier['appInstances'] || []).collect {|it| it['instance']}.flatten().compact
          end
          #"(#{instances.count})"
          "(#{instances.count}) #{instances.collect {|it| it['name'] }.join(',')}"
        },
        "Containers" => lambda {|it| 
          #it['containerCount'] 
          containers = []
          app_tiers = it['appTiers'] || []
          app_tiers.each do |app_tier|
            containers += (app_tier['appInstances'] || []).collect {|it| it['instance']['containers']}.flatten().compact
          end
          #"(#{containers.count})"
          "(#{containers.count}) #{containers.collect {|it| it }.join(',')}"
        },
        "Status" => lambda {|it| format_app_status(it) }
      }
      if app['blueprint'].nil?
        description_cols.delete("Blueprint")
      end
      # if app['description'].nil?
      #   description_cols.delete("Description")
      # end
      print_description_list(description_cols, app)

      stats = app['stats']
      if app['instanceCount'].to_i > 0
        print_h2 "App Usage", options
        print_stats_usage(stats, {include: [:memory, :storage]})
      end

      if app_tiers.empty?
        puts yellow, "This app is empty", reset
      else
        app_tiers.each do |app_tier|
          # print_h2 "Tier: #{app_tier['tier']['name']}", options
          print_h2 "#{app_tier['tier']['name']}", options
          print cyan
          instances = (app_tier['appInstances'] || []).collect {|it| it['instance']}
          if instances.empty?
            puts yellow, "This tier is empty", reset
          else
            instances_rows = instances.collect do |instance|
              # JD: fix bug here, status is not returned because withStats: false !?
              status_string = instance['status'].to_s
              if status_string == 'running'
                status_string = "#{green}#{status_string.upcase}#{cyan}"
              elsif status_string == 'provisioning'
                status_string = "#{cyan}#{status_string.upcase}#{cyan}"
              elsif status_string == 'stopped' or status_string == 'failed'
                status_string = "#{red}#{status_string.upcase}#{cyan}"
              elsif status_string == 'unknown'
                status_string = "#{white}#{status_string.upcase}#{cyan}"
              else
                status_string = "#{yellow}#{status_string.upcase}#{cyan}"
              end
              connection_string = ''
              if !instance['connectionInfo'].nil? && instance['connectionInfo'].empty? == false
                connection_string = "#{instance['connectionInfo'][0]['ip']}:#{instance['connectionInfo'][0]['port']}"
              end
              {id: instance['id'], name: instance['name'], connection: connection_string, environment: instance['instanceContext'], nodes: instance['containers'].count, status: status_string, type: instance['instanceType']['name'], group: !instance['group'].nil? ? instance['group']['name'] : nil, cloud: !instance['cloud'].nil? ? instance['cloud']['name'] : nil}
            end
            instances_rows = instances_rows.sort {|x,y| x[:id] <=> y[:id] } #oldest to newest..
            print cyan
            print as_pretty_table(instances_rows, [:id, :name, :cloud, :type, :environment, :nodes, :connection, :status], {border_style: options[:border_style]})
            print reset
            print "\n"
          end
        end
      end
      print cyan


      # refresh until a status is reached
      if options[:refresh_until_status]
        if options[:refresh_interval].nil? || options[:refresh_interval].to_f < 0
          options[:refresh_interval] = 5
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(app['status'])
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

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      #build_option_type_options(opts, options, update_app_option_types(false))
      opts.on( '-g', '--group GROUP', "Group Name or ID" ) do |val|
        options[:group] = val
      end
      opts.on( '--name VALUE', String, "Name" ) do |val|
        options[:name] = val
      end
      opts.on( '--description VALUE', String, "Description" ) do |val|
        options[:description] = val
      end
      opts.on( '--environment VALUE', String, "Environment" ) do |val|
        options[:environment] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run])
      opts.footer = "Update an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} update expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?

      payload = {}
      if options[:payload]
        payload = options[:payload]
      else
        payload = {
          'app' => {id: app["id"]}
        }
        params = options[:options] || {}
        if options[:name]
          params['name'] = options[:name]
        end
        if options[:description]
          params['description'] = options[:description]
        end
        if options[:environment]
          # params['environment'] = options[:environment]
          params['appContext'] = options[:environment]
        end
        if options[:group]
          group = find_group_by_name_or_id_for_provisioning(options[:group])
          return 1 if group.nil?
          params['group'] = {'id' => group['id'], 'name' => group['name']}
        end
        if params.empty?
          print_red_alert "Specify atleast one option to update"
          puts optparse
          return 1
        end
        payload['app'].merge!(params)
        # api bug requires this to be at the root level as well right now
        if payload['app'] && payload['app']['group']
          payload['group'] = payload['app']['group']
        end
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.update(app["id"], payload)
        return
      end

      json_response = @apps_interface.update(app["id"], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Updated app #{app['name']}"
        list([])
        # details_options = [payload['app']['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  def add_instance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [instance] [tier]")
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "Add an existing instance to an app.\n" +
                    "[app] is required. This is the name or id of an app." + "\n" +
                    "[instance] is required. This is the name or id of an instance." + "\n" +
                    "[tier] is required. This is the name of the tier."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 3
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add-instance expects 1-3 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
      if args[2] && args[2] !~ /\A\-/
        options[:tier_name] = args[2]
      end
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      # Only supports adding an existing instance right now..

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']

      if options[:tier_name]
        payload[:tierName] = options[:tier_name]
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tier', 'fieldLabel' => 'Tier', 'type' => 'text', 'required' => true, 'description' => 'Enter the name of the tier'}], options[:options])
        payload[:tierName] = v_prompt['tier']
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.add_instance(app['id'], payload)
        return
      end
      json_response = @apps_interface.add_instance(app['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Added instance #{instance['name']} to app #{app['name']}"
        #get(app['id'])
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
      opts.banner = subcommand_usage("[app]")
      #JD: UI defaults to on, but perhaps better to be explicate for now.
      opts.on('--remove-instances [on|off]', ['on','off'], "Remove instances. Default is off.") do |val|
        query_params[:removeInstances] = val.nil? ? 'on' : val
      end
      opts.on('--preserve-volumes [on|off]', ['on','off'], "Preserve Volumes. Default is off. Applies to certain types only.") do |val|
        query_params[:preserveVolumes] = val.nil? ? 'on' : val
      end
      opts.on( '--keep-backups', '--keep-backups', "Preserve copy of backups" ) do
        query_params[:keepBackups] = 'on'
      end
      opts.on('--releaseEIPs [on|off]', ['on','off'], "Release EIPs. Default is on. Applies to Amazon only.") do |val|
        query_params[:releaseEIPs] = val.nil? ? 'on' : val
      end
      opts.on( '-f', '--force', "Force Delete" ) do
        query_params[:force] = 'on'
      end
      build_common_options(opts, options, [:json, :dry_run, :quiet, :auto_confirm])
      opts.footer = "Delete an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the app '#{app['name']}'?", options)
        return 9
      end
      # JD: removeVolumes to maintain the old behavior with pre-3.5.2 appliances, remove me later
      if query_params[:preserveVolumes].nil?
        query_params[:removeVolumes] = 'on'
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.destroy(app['id'], query_params)
        return
      end
      json_response = @apps_interface.destroy(app['id'], query_params)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        print_green_success "Removed app #{app['name']}"
        #list([])
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_instance(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [instance]")
      build_common_options(opts, options, [:options, :json, :dry_run])
      opts.footer = "Remove an instance from an app.\n" +
                    "[app] is required. This is the name or id of an app." + "\n" +
                    "[instance] is required. This is the name or id of an instance."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} remove-instance expects 1-2 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    # optional [tier] and [instance] arguments
    if args[1] && args[1] !~ /\A\-/
      options[:instance_name] = args[1]
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      payload = {}

      if options[:instance_name]
        instance = find_instance_by_name_or_id(options[:instance_name])
      else
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'instance', 'fieldLabel' => 'Instance', 'type' => 'text', 'required' => true, 'description' => 'Enter the instance name or id'}], options[:options])
        instance = find_instance_by_name_or_id(v_prompt['instance'])
      end
      payload[:instanceId] = instance['id']
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.remove_instance(app['id'], payload)
        return
      end

      json_response = @apps_interface.remove_instance(app['id'], payload)

      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed instance #{instance['name']} from app #{app['name']}"
        #list([])
        # details_options = [app['name']]
        # details(details_options)
      end

    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def logs(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:list, :json, :dry_run])
      opts.footer = "List logs for an app.\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count !=1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} logs expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      containers = []
      app['appTiers'].each do |app_tier|
        app_tier['appInstances'].each do |app_instance|
          containers += app_instance['instance']['containers']
        end
      end
      params = {}
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @logs_interface.dry.container_logs(containers, params)
        return
      end
      logs = @logs_interface.container_logs(containers, params)
      if options[:json]
        puts as_json(logs, options)
        return 0
      else
        title = "App Logs: #{app['name']}"
        subtitles = []
        if params[:query]
          subtitles << "Search: #{params[:query]}".strip
        end
        # todo: startMs, endMs, sorts insteaad of sort..etc
        print_h1 title, subtitles, options
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
          puts "[#{log_entry['ts']}] #{log_level} - #{log_entry['message'].to_s.strip}"
        end
        print reset,"\n"
        return 0
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def stop(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Stop an app.\n" +
                    "[app] is required. This is the name or id of an app. Supports 1-N [app] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to stop #{id_list.size == 1 ? 'app' : 'apps'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _stop(arg, options)
    end
  end

  def _stop(app_id, options)
    app = find_app_by_name_or_id(app_id)
    return 1 if app.nil?
    tier_records = extract_app_tiers(app)
    if options[:dry_run]
      print_h1 "Dry Run", [], options
    end
    tier_records.each do |tier_record|
      tier_record[:instances].each do |instance|
        stop_cmd = "instances stop #{instance['id']} -y"
        if options[:dry_run]
          puts stop_cmd
        else
          my_terminal.execute(stop_cmd)
        end
      end
    end
    return 0
  end

  def start(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Start an app.\n" +
                    "[app] is required. This is the name or id of an app. Supports 1-N [app] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to start #{id_list.size == 1 ? 'app' : 'apps'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _start(arg, options)
    end
  end

  def _start(app_id, options)
    app = find_app_by_name_or_id(app_id)
    return 1 if app.nil?
    tier_records = extract_app_tiers(app)
    if options[:dry_run]
      print_h1 "Dry Run", [], options
    end
    tier_records.each do |tier_record|
      tier_record[:instances].each do |instance|
        start_cmd = "instances start #{instance['id']} -y"
        if options[:dry_run]
          puts start_cmd
        else
          my_terminal.execute(start_cmd)
        end
      end
    end
    return 0
  end

  def restart(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Restart an app.\n" +
                    "[app] is required. This is the name or id of an app. Supports 1-N [app] arguments."
    end
    optparse.parse!(args)
    if args.count < 1
      puts_error "[id] argument is required"
      puts_error optparse
      return 1
    end
    connect(options)
    id_list = parse_id_list(args)
    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to restart #{id_list.size == 1 ? 'app' : 'apps'} #{anded_list(id_list)}?", options)
      return 9, "aborted command"
    end
    return run_command_for_each_arg(id_list) do |arg|
      _restart(arg, options)
    end
  end

  def _restart(app_id, options)
    app = find_app_by_name_or_id(app_id)
    return 1 if app.nil?
    tier_records = extract_app_tiers(app)
    if options[:dry_run]
      print_h1 "Dry Run", [], options
    end
    tier_records.each do |tier_record|
      tier_record[:instances].each do |instance|
        restart_cmd = "instances restart #{instance['id']} -y"
        if options[:dry_run]
          puts restart_cmd
        else
          my_terminal.execute(restart_cmd)
        end
      end
    end
    return 0
  end

  def firewall_disable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} firewall-disable expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_disable(app['id'])
        return
      end
      @apps_interface.firewall_disable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def firewall_enable(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} firewall-enable expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.firewall_enable(app['id'])
        return
      end
      @apps_interface.firewall_enable(app['id'])
      security_groups([args[0]])
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def security_groups(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} security-groups expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.security_groups(app['id'])
        return
      end
      json_response = @apps_interface.security_groups(app['id'])
      securityGroups = json_response['securityGroups']
      print_h1 "Morpheus Security Groups for App: #{app['name']}", options
      print cyan
      print_description_list({"Firewall Enabled" => lambda {|it| format_boolean it['firewallEnabled'] } }, json_response)
      if securityGroups.empty?
        print cyan,"\n","No security groups currently applied.",reset,"\n"
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
    params = {}
    clear_or_secgroups_specified = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [--clear] [-s]")
      opts.on( '-c', '--clear', "Clear all security groups" ) do
        params[:securityGroupIds] = []
        clear_or_secgroups_specified = true
      end
      opts.on( '-s', '--secgroups SECGROUPS', "Apply the specified comma separated security group ids" ) do |secgroups|
        params[:securityGroupIds] = secgroups.split(",")
        clear_or_secgroups_specified = true
      end
      opts.on( '-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      build_common_options(opts, options, [:json, :dry_run])
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} apply-security-groups expects 1 argument and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    if !clear_or_secgroups_specified
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} apply-security-groups requires either --clear or --secgroups\n#{optparse}"
      return 1
    end

    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      payload = params
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.apply_security_groups(app['id'], payload)
        return
      end
      @apps_interface.apply_security_groups(app['id'], payload)
      security_groups([args[0]])
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
      opts.banner = subcommand_usage("[app]")
      # opts.on( '-n', '--node NODE_ID', "Scope history to specific Container or VM" ) do |node_id|
      #   options[:node_id] = node_id.to_i
      # end
      opts.on( nil, '--events', "Display sub processes (events)." ) do
        options[:show_events] = true
      end
      opts.on( nil, '--output', "Display process output." ) do
        options[:show_output] = true
      end
      opts.on(nil, '--details', "Display more details. Shows everything, untruncated." ) do
        options[:show_events] = true
        options[:show_output] = true
        options[:details] = true
      end
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List historical processes for a specific app.\n" + 
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)

    if args.count != 1
      puts optparse
      return 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])

      instance_ids = []
      app['appTiers'].each do |app_tier|
        app_tier['appInstances'].each do |app_instance|
          instance_ids << app_instance['instance']['id']
        end
      end
      
      # container_ids = instance['containers']
      # if options[:node_id] && container_ids.include?(options[:node_id])
      #   container_ids = [options[:node_id]]
      # end
      params = {}
      params['instanceIds'] = instance_ids
      params.merge!(parse_list_options(options))
      # params[:query] = params.delete(:phrase) unless params[:phrase].nil?
      @processes_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @processes_interface.dry.list(params)
        return
      end
      json_response = @processes_interface.list(params)
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

        title = "App History: #{app['name']}"
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
              error: format_process_error(process),
              output: format_process_output(process)
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

  private

  def extract_app_tiers(app)
    tier_rows = []
    begin
      app_tiers = app['appTiers'] || []
      sorted_app_tiers = app_tiers.sort {|a,b| a['bootSequence'] <=> b['bootSequence'] }
      sorted_app_tiers.each do |app_tier|
        tier_name = app_tier['tier']['name']
        boot_sequence = app_tier['bootSequence'] || 0
        instances = (app_tier['appInstances'] || []).collect {|it| it['instance']}
        row = {tier_name: tier_name, boot_sequence: boot_sequence, instances: instances}
        tier_rows << row
      end
    rescue => ex
      Morpheus::Logging::DarkPrinter.puts "Error extracting app instances: #{ex}" if Morpheus::Logging.debug?
    end
    return tier_rows
  end

  # def add_app_option_types(connected=true)
  #   [
  #     {'fieldName' => 'blueprint', 'fieldLabel' => 'Blueprint', 'type' => 'select', 'selectOptions' => (connected ? get_available_blueprints() : []), 'required' => true, 'defaultValue' => 'existing', 'description' => "The blueprint to use. The default value is 'existing' which means no template, for creating a blank app and adding existing instances."},
  #     {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this app'},
  #     {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
  #     {'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'selectOptions' => (connected ? get_available_groups() : []), 'required' => false},
  #     {'fieldName' => 'cloud', 'fieldLabel' => 'Default Cloud', 'type' => 'select', 'selectOptions' => [], 'required' => true},
  #     {'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'text', 'required' => false},
  #   ]
  # end

  # def update_app_option_types(connected=true)
  #   list = add_app_option_types(connected)
  #   list = list.reject {|it| ["blueprint", "group"].include? it['fieldName'] }
  #   list.each {|it| it['required'] = false }
  #   list
  # end

  def find_app_by_id(id)
    app_results = @apps_interface.get(id.to_i)
    if app_results['app'].empty?
      print_red_alert "App not found by id #{id}"
      exit 1
    end
    return app_results['app']
  end

  def find_app_by_name(name)
    app_results = @apps_interface.get({name: name})
    if app_results['apps'].empty?
      print_red_alert "App not found by name #{name}"
      exit 1
    end
    return app_results['apps'][0]
  end

  def find_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_app_by_id(val)
    else
      return find_app_by_name(val)
    end
  end

  def print_apps_table(apps, opts={})
    
    table_color = opts[:color] || cyan
    rows = apps.collect do |app|
      tiers_str = format_app_tiers(app)
      instances_str = (app['instanceCount'].to_i == 1) ? "1 Instance" : "#{app['instanceCount']} Instances"
      containers_str = (app['containerCount'].to_i == 1) ? "1 Container" : "#{app['containerCount']} Containers"
      stats = app['stats']
      # app_stats = app['appStats']
      cpu_usage_str = !stats ? "" : generate_usage_bar((stats['cpuUsage'] || stats['cpuUsagePeak']).to_f, 100, {max_bars: 10})
      memory_usage_str = !stats ? "" : generate_usage_bar(stats['usedMemory'], stats['maxMemory'], {max_bars: 10})
      storage_usage_str = !stats ? "" : generate_usage_bar(stats['usedStorage'], stats['maxStorage'], {max_bars: 10})
      {
        id: app['id'],
        name: app['name'],
        group: app['group'] ? app['group']['name'] : app['siteId'],
        tiers: tiers_str,
        instances: instances_str,
        containers: containers_str,
        account: app['account'] ? app['account']['name'] : nil,
        status: format_app_status(app, table_color),
        cpu: cpu_usage_str + cyan,
        memory: memory_usage_str + table_color,
        storage: storage_usage_str + table_color
        #dateCreated: format_local_dt(app['dateCreated'])
      }
    end

    columns = [
      :id,
      :name,
      :group,
      :tiers,
      :instances,
      :containers,
      #:account,
      :status,
      #{:dateCreated => {:display_name => "Date Created"} }
    ]
    term_width = current_terminal_width()
    if term_width > 120
      columns += [
        {:cpu => {:display_name => "MAX CPU"} },
        :memory,
        :storage
      ]
    end
    # custom pretty table columns ...
    # if options[:include_fields]
    #   columns = options[:include_fields]
    # end
    # print cyan
    print as_pretty_table(rows, columns, opts) #{color: table_color}
    print reset
  end

  def format_app_status(app, return_color=cyan)
    out = ""
    status_string = app['status'] || app['appStatus'] || ''
    if status_string == 'running'
      out = "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'provisioning'
      out = "#{cyan}#{status_string.upcase}#{cyan}"
    elsif status_string == 'stopped' or status_string == 'failed'
      out = "#{red}#{status_string.upcase}#{return_color}"
    elsif status_string == 'unknown'
      out = "#{yellow}#{status_string.upcase}#{return_color}"
    elsif status_string == 'warning' && app['instanceCount'].to_i == 0
      # show this instead of WARNING
      out =  "#{cyan}EMPTY#{return_color}"
    else
      out =  "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

  def format_app_tiers(app)
    out = ""
    begin
      app_tiers = app['appTiers']
      if app_tiers
        app_tier_names = app_tiers.collect { |app_tier| app_tier['tier']['name'] }
        out << app_tier_names.join(", ")
      end
      if out.empty?
        #out = "(Empty)"
      end
    rescue => ex
      Morpheus::Logging::DarkPrinter.puts "A formatting exception occured: #{ex}" if Morpheus::Logging.debug?
    end
    out
  end

  def get_available_blueprints(refresh=false)
    if !@available_blueprints || refresh
      #results = @options_interface.options_for_source('appTemplates',{}) # still exists
      results = @options_interface.options_for_source('blueprints',{})
      @available_blueprints = results['data'].collect {|it|
        {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
      }
      default_option = {"id" => "existing", "name" => "Existing Instances", "value" => "existing", "type" => "morpheus"}
      @available_blueprints.unshift(default_option)
    end
    #puts "get_available_blueprints() rtn: #{@available_blueprints.inspect}"
    return @available_blueprints
  end

  def get_available_environments(refresh=false)
    if !@available_environments || refresh
      # results = @options_interface.options_for_source('environments',{})
      # @available_environments = results['data'].collect {|it|
      #   {"id" => it["value"], "name" => it["name"], "value" => it["value"]}
      # }
      # todo: api call
      @available_environments = [
        {'name' => 'Dev', 'value' => 'Dev'},
        {'name' => 'Test', 'value' => 'Test'},
        {'name' => 'Staging', 'value' => 'Staging'},
        {'name' => 'Production', 'value' => 'Production'}
      ]
    end
    #puts "get_available_environments() rtn: #{@available_environments.inspect}"
    return @available_environments
  end

  def find_blueprint_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_blueprint_by_id(val)
    else
      return find_blueprint_by_name(val)
    end
  end

  def find_blueprint_by_id(id)
    begin
      json_response = @blueprints_interface.get(id.to_i)
      return json_response['blueprint']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Blueprint not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_blueprint_by_name(name)
    blueprints = @blueprints_interface.list({name: name.to_s})['blueprints']
    if blueprints.empty?
      print_red_alert "Blueprint not found by name #{name}"
      return nil
    elsif blueprints.size > 1
      print_red_alert "#{blueprints.size} blueprints found by name #{name}"
      # print_blueprints_table(blueprints, {color: red})
      rows = blueprints.collect { |it| {id: it['id'], name: it['name']} }
      print red
      print as_pretty_table(rows, [:id, :name], {color:red})
      print reset,"\n"
      return nil
    else
      return blueprints[0]
    end
  end

  # lookup scoped instance config in a blueprint
  # this only finds one right now
  # def tmplCfg = getConfigMap(appTemplateConfig?.tiers?.getAt(tierName)?.instances?.getAt(index), opts.environment, opts.group, instanceOpts.instance.cloud?: opts?.defaultCloud?.name)
  def get_scoped_instance_config(instance_config, env_name, group_name, cloud_name)
      config = instance_config.clone
      if env_name.to_s != '' && config['environments'] && config['environments'][env_name]
        config = config['environments'][env_name].clone
      end
      if group_name.to_s != '' && config['groups'] && config['groups'][group_name]
        config = config['groups'][group_name].clone
      end
      if cloud_name.to_s != '' && config['clouds'] && config['clouds'][cloud_name]
        config = config['clouds'][cloud_name].clone
      end
      config.delete('environments')
      config.delete('groups')
      config.delete('clouds')
      # puts "get_scoped_instance_config(instance_config, #{env_name}, #{group_name}, #{cloud_name})"
      # puts "returned config: #{config}"
      return config
  end

  # def getConfigMap(instance, env, group, cloud) {
  #   def  configMap = instance
  #   if(env && instance?.environments) {
  #     def envName = (env instanceof String? env : env?.name)
  #     configMap = instance?.environments?.getAt(envName) ?: instance
  #   }
  #   if(group && configMap?.groups) {
  #     if (group instanceof String) {
  #       configMap = configMap?.groups?.getAt(group) ?: configMap
  #     }
  #     else {
  #       configMap = configMap?.groups?.getAt(group?.name) ?: configMap
  #     }
  #   }
  #   if(cloud && configMap?.clouds) {
  #     return configMap?.clouds?.getAt(cloud) ?: configMap
  #   }
  #   return configMap
  # }
end
