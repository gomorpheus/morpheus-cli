require 'morpheus/cli/cli_command'

class Morpheus::Cli::Apps
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::AccountsHelper # needed? replace with OptionSourceHelper
  include Morpheus::Cli::OptionSourceHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::ProcessesHelper
  include Morpheus::Cli::LogsHelper
  set_command_name :apps
  set_command_description "View and manage apps."
  register_subcommands :list, :count, :get, :view, :add, :update, :remove, :cancel_removal, :add_instance, :remove_instance, :logs, :security_groups, :apply_security_groups, :history
  register_subcommands :'prepare-apply' => :prepare_apply
  register_subcommands :apply
  register_subcommands :refresh
  register_subcommands :stop, :start, :restart
  register_subcommands :wiki, :update_wiki
  #register_subcommands :firewall_disable, :firewall_enable
  #register_subcommands :validate # add --validate instead
  alias_subcommand :details, :get
  set_default_subcommand :list

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @accounts_interface = @api_client.accounts
    @account_users_interface = @api_client.account_users
    @apps_interface = @api_client.apps
    @blueprints_interface = @api_client.blueprints
    @instance_types_interface = @api_client.instance_types
    @library_layouts_interface = @api_client.library_layouts
    @instances_interface = @api_client.instances
    @options_interface = @api_client.options
    @groups_interface = @api_client.groups
    @clouds_interface = @api_client.clouds
    @logs_interface = @api_client.logs
    @processes_interface = @api_client.processes
    @active_group_id = Morpheus::Cli::Groups.active_groups[@appliance_name]
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on( '-t', '--type TYPE', "Filter by type" ) do |val|
        options[:type] = val
      end
      opts.on( '--blueprint BLUEPRINT', "Blueprint Name or ID" ) do |val|
        options[:blueprint] = val
      end
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val
      end
      opts.on( '--created-by USER', "[DEPRECATED] Alias for --owner" ) do |val|
        options[:owner] = val
      end
      opts.add_hidden_option('--created-by')
      opts.on('--pending-removal', "Include apps pending removal.") do
        options[:showDeleted] = true
      end
      opts.on('--pending-removal-only', "Only apps pending removal.") do
        options[:deleted] = true
      end
      opts.on('--environment ENV', "Filter by environment code (appContext)") do |val|
        # environment means appContext
        params['environment'] = (params['environment'] || []) + val.to_s.split(',').collect {|s| s.strip }.select {|s| s != "" }
      end
      opts.on('--status STATUS', "Filter by status.") do |val|
        params['status'] = (params['status'] || []) + val.to_s.split(',').collect {|s| s.strip }.select {|s| s != "" }
      end
      opts.on('-a', '--details', "Display all details: memory and storage usage used / max values." ) do
        options[:details] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = "List apps."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    
    if options[:type]
      params['type'] = [options[:type]].flatten.collect {|it| it.to_s.strip.split(",") }.flatten.collect {|it| it.to_s.strip }
    end
    if options[:blueprint]
      blueprint_ids = [options[:blueprint]].flatten.collect {|it| it.to_s.strip.split(",") }.flatten.collect {|it| it.to_s.strip }
      params['blueprintId'] = blueprint_ids.collect do |blueprint_id|
        if blueprint_id.to_s =~ /\A\d{1,}\Z/
          return blueprint_id
        else
          blueprint = find_blueprint_by_name_or_id(blueprint_id)
          return 1 if blueprint.nil?
          blueprint['id']
        end
      end
    end
    if options[:owner]
      owner_ids = [options[:owner]].flatten.collect {|it| it.to_s.strip.split(",") }.flatten.collect {|it| it.to_s.strip }
      params['ownerId'] = owner_ids.collect do |owner_id|
        if owner_id.to_s =~ /\A\d{1,}\Z/
          return owner_id
        else
          user = find_available_user_option(owner_id)
          return 1 if user.nil?
          user['id']
        end
      end
    end
    params.merge!(parse_list_options(options))
    account = nil
    if options[:owner]
      created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
      return if created_by_ids.nil?
      params['createdBy'] = created_by_ids
      # params['ownerId'] = created_by_ids # 4.2.1+
    end

    params['showDeleted'] = options[:showDeleted] if options.key?(:showDeleted)
    params['deleted'] = options[:deleted] if options.key?(:deleted)

    @apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @apps_interface.dry.list(params)
      return
    end
    json_response = @apps_interface.list(params)
    render_response(json_response, options, "apps") do
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
    end
    return 0, nil
  end

  def count(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[options]")
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
      opts.footer = "Get the number of apps."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params = {}
      params.merge!(parse_list_options(options))
      account = nil
      if options[:owner]
        created_by_ids = find_all_user_ids(account ? account['id'] : nil, options[:owner])
        return if created_by_ids.nil?
        params['createdBy'] = created_by_ids
        # params['ownerId'] = created_by_ids # 4.2.1+
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.list(params)
        return
      end
      json_response = @apps_interface.list(params)
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
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_interval] = val.to_s.empty? ? default_refresh_interval : val.to_f
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
            #print_red_alert "Blueprint not found by name or id '#{blueprint_id}'"
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
        cloud = nil
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
        selected_environment = nil
        available_environments = get_available_environments()
        if options[:environment]
          payload['environment'] = options[:environment]
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'select', 'selectOptions' => available_environments}], options[:options], @api_client)
          payload['environment'] = v_prompt['environment'] unless v_prompt['environment'].to_s.empty?
        end
        selected_environment = nil
        if payload['environment']
          selected_environment = available_environments.find {|it| it['code'] == payload['environment'] || it['name'] == payload['environment'] }
          if selected_environment.nil?
            print_red_alert "Environment not found by name or code '#{payload['environment']}'"
            return 1
          end
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
                      # cloud_id = nil
                      # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'selectOptions' => scoped_available_clouds, 'defaultValue' => cloud ? cloud['name'] : nil}], options[:options])
                      # cloud_id = v_prompt['cloud'] unless v_prompt['cloud'].to_s.empty?
                      # if cloud_id
                      #   # cloud = find_cloud_by_name_or_id_for_provisioning(group['id'], cloud_id)
                      #   cloud = scoped_available_clouds.find {|it| it['name'] == cloud_id.to_s } || scoped_available_clouds.find {|it| it['id'].to_s == cloud_id.to_s }
                      #   return 1 if cloud.nil?
                      # else
                      #   # prompt still happens inside get_scoped_instance_config
                      # end
                      
                      
                      # prompt for the cloud for this instance
                      # the cloud is part of finding the scoped config in the blueprint
                      scoped_instance_config = get_scoped_instance_config(instance_config.clone, selected_environment ? selected_environment['name'] : nil, group ? group['name'] : nil, cloud ? cloud['name'] : nil)

                      # now configure an instance like normal, use the config as default options with :always_prompt
                      instance_prompt_options = {}
                      instance_prompt_options[:group] = group ? group['id'] : nil
                      #instance_prompt_options[:cloud] = cloud ? cloud['name'] : nil
                      instance_prompt_options[:default_cloud] = cloud ? cloud['name'] : nil
                      instance_prompt_options[:environment] = selected_environment ? selected_environment['code'] : nil
                      instance_prompt_options[:default_security_groups] = scoped_instance_config['securityGroups'] ? scoped_instance_config['securityGroups'] : nil

                      instance_prompt_options[:no_prompt] = options[:no_prompt]
                      #instance_prompt_options[:always_prompt] = options[:no_prompt] != true # options[:always_prompt]
                      instance_prompt_options[:options] = scoped_instance_config # meh, actually need to make these default values instead..
                      #instance_prompt_options[:options][:always_prompt] = instance_prompt_options[:no_prompt] != true
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
                      help_field_prefix = "#{tier_name}.#{instance_index}" 
                      instance_prompt_options[:help_field_prefix] = help_field_prefix
                      instance_prompt_options[:options][:help_field_prefix] = help_field_prefix
                      instance_prompt_options[:locked_fields] = scoped_instance_config['lockedFields']
                      instance_prompt_options[:for_app] = true
                      # this provisioning helper method handles all (most) of the parsing and prompting
                      scoped_instance_config = Marshal.load( Marshal.dump(scoped_instance_config) )
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
                      final_config.delete('lockedFields')
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
              # looks for special error format like instances.instanceErrors 
              if json_response['errors'] && json_response['errors']['instances']
                json_response['errors']['instances'].each do |error_obj|
                  tier_name = error_obj['tier']
                  instance_index = error_obj['index']
                  instance_errors = error_obj['instanceErrors']
                  print_error red, "#{tier_name} : #{instance_index}", reset, "\n"
                  if instance_errors
                    instance_errors.each do |err_key, err_msg|
                      print_error red, " * #{err_key} : #{err_msg}", reset, "\n"
                    end
                  end
                end
              else
                # a default way to print errors
                (json_response['errors'] || {}).each do |error_key, error_msg|
                  if error_key != 'instances'
                    print_error red, " * #{error_key} : #{error_msg}", reset, "\n"
                  end
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
        get_args = [app['id']] + (options[:remote] ? ["-r",options[:remote]] : []) + (options[:refresh_interval] ? ['--refresh', options[:refresh_interval].to_s] : [])
        get(get_args)
      end
      return 0
    rescue RestClient::Exception => e
      #print_rest_exception(e, options)
      json_response = nil
      begin
        json_response = JSON.parse(e.response.to_s)
      rescue TypeError, JSON::ParserError => ex
        print_error red, "Failed to parse JSON response: #{ex}", reset, "\n"
      end
      if json_response && (json_response['errors'].nil? || json_response['errors'].empty?)
        # The default way to print error msg
        print_rest_exception(e, options)
      else
        # print errors and look for special errors.instances
        # todo: just handle sub lists of errors default error handler (print_rest_exception)
        (json_response['errors'] || {}).each do |error_key, error_msg|
          if error_key != 'instances'
            print_error red, " * #{error_key} : #{error_msg}", reset, "\n"
          end
        end
        # looks for special error format like instances.instanceErrors 
        if json_response['errors'] && json_response['errors']['instances']
          json_response['errors']['instances'].each do |error_obj|
            tier_name = error_obj['tier']
            instance_index = error_obj['index']
            instance_errors = error_obj['instanceErrors']
            print_error red, "#{tier_name} : #{instance_index}", reset, "\n"
            if instance_errors
              instance_errors.each do |err_key, err_msg|
                print_error red, " * #{err_key} : #{err_msg}", reset, "\n"
              end
            end
          end
        end
      end
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      opts.on('--refresh [SECONDS]', String, "Refresh until status is running,failed. Default interval is #{default_refresh_interval} seconds.") do |val|
        options[:refresh_until_status] ||= "running,failed"
        if !val.to_s.empty?
          options[:refresh_interval] = val.to_f
        end
      end
      opts.on('--refresh-until STATUS', String, "Refresh until a specified status is reached.") do |val|
        options[:refresh_until_status] = val.to_s.downcase
      end
      build_standard_get_options(opts, options)
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

  def _get(id, options={})
    app = nil
    if id.to_s !~ /\A\d{1,}\Z/
      app = find_app_by_name_or_id(id)
      id = app['id']
    end
    @apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @apps_interface.dry.get(id)
      return
    end
    json_response = @apps_interface.get(id.to_i)
    render_response(json_response, options, 'app') do
      app = json_response['app']
      app_tiers = app['appTiers']
      print_h1 "App Details", [], options
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Description" => 'description',
        "Type" => lambda {|it| 
          if it['type']
            format_blueprint_type(it['type']) 
          else
            format_blueprint_type(it['blueprint'] ? it['blueprint']['type'] : nil) 
          end
        },
        "Blueprint" => lambda {|it| it['blueprint'] ? it['blueprint']['name'] : '' },
        "Group" => lambda {|it| it['group'] ? it['group']['name'] : it['siteId'] },
        "Environment" => lambda {|it| it['appContext'] },
        "Owner" => lambda {|it| it['owner'] ? it['owner']['username'] : '' },
        #"Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
        "Tiers" => lambda {|it| 
          # it['instanceCount']
          tiers = []
          app_tiers = it['appTiers'] || []
          app_tiers.each do |app_tier|
            tiers << app_tier['tier']
          end
          "(#{(tiers || []).size()}) #{tiers.collect {|it| it.is_a?(Hash) ? it['name'] : it }.join(',')}"
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

      description_cols["Removal Date"] = lambda {|it| format_local_dt(it['removalDate'])} if app['status'] == 'pendingRemoval'

      # if app['blueprint'].nil?
      #   description_cols.delete("Blueprint")
      # end
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
        #puts yellow, "This app is empty", reset
        print reset,"\n"
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
          options[:refresh_interval] = default_refresh_interval
        end
        statuses = options[:refresh_until_status].to_s.downcase.split(",").collect {|s| s.strip }.select {|s| !s.to_s.empty? }
        if !statuses.include?(app['status'])
          print cyan, "Refreshing in #{options[:refresh_interval] > 1 ? options[:refresh_interval].to_i : options[:refresh_interval]} seconds"
          sleep_with_dots(options[:refresh_interval])
          print "\n"
          _get(app['id'], options)
        end
      end
    end
    return 0, nil
  end

  def update(args)
    params, payload, options = {}, {}, {}
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
      opts.on( '--owner USER', "Owner Username or ID" ) do |val|
        options[:owner] = val == 'null' ? nil : val
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
      if options[:payload]
        payload = options[:payload]
      end
      payload['app'] ||= {}
      payload.deep_merge!({'app' => parse_passed_options(options)})
      if options[:name]
        payload['app']['name'] = options[:name]
      end
      if options[:description]
        payload['app']['description'] = options[:description]
      end
      if options[:environment]
        # payload['app']['environment'] = options[:environment]
        payload['app']['appContext'] = options[:environment]
      end
      if options[:group]
        group = find_group_by_name_or_id_for_provisioning(options[:group])
        return 1 if group.nil?
        payload['app']['group'] = {'id' => group['id'], 'name' => group['name']}
      end
      if options.key?(:owner)
        owner_id = options[:owner]
        if owner_id.to_s.empty?
          # allow clearing
          owner_id = nil
        elsif options[:owner]
          if owner_id.to_s =~ /\A\d{1,}\Z/
            # allow id without lookup
          else
            user = find_available_user_option(owner_id)
            return 1 if user.nil?
            owner_id = user['id']
          end
        end
        payload['app']['ownerId'] = owner_id
      end
      if payload['app'] && payload['app'].empty?
        payload.delete('app')
      end
      if payload.empty?
        raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.update(app["id"], payload)
        return
      end
      json_response = @apps_interface.update(app["id"], payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      print_green_success "Updated app #{app['name']}"
      get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def refresh(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Refresh an app.
[app] is required. This is the name or id of an app.
This is only supported by certain types of apps.
EOT
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?
      # construct request
      params.merge!(parse_query_options(options))
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        # raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to refresh this app: #{app['name']}?")
        return 9, "aborted command"
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.refresh(app["id"], params, payload)
        return
      end
      json_response = @apps_interface.refresh(app["id"], params, payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      print_green_success "Refreshed app #{app['name']}"
      return get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def prepare_apply(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Prepare to apply an app.
[app] is required. This is the name or id of an app.
Template parameter values can be applied with -O templateParameter.foo=bar
This only prints the app configuration that would be applied.
It does not make any updates.
This is only supported by certain types of apps.
EOT
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?
      # construct request
      params.merge!(parse_query_options(options))
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        # raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.prepare_apply(app["id"], params, payload)
        return
      end
      json_response = @apps_interface.prepare_apply(app["id"], params, payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      # print_green_success "Prepared to apply app: #{app['name']}"
      print_h1 "Prepared App: #{app['name']}"
      app_config = json_response['data'] 
      # app_config = json_response if app_config.nil?
      puts as_yaml(app_config, options)
      #return get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      print "\n", reset
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def apply(args)
    params, payload, options = {}, {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_standard_update_options(opts, options, [:auto_confirm])
      opts.footer = <<-EOT
Apply an app.
[app] is required. This is the name or id of an app.
Template parameter values can be applied with -O templateParameter.foo=bar
This is a way to apply an app with new configuration parameters to an app. 
This prints the app configuration that would be applied.
It does not make any updates.
This is only supported by certain types of apps.
EOT
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(', ')}\n#{optparse}"
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?
      # construct request
      params.merge!(parse_query_options(options))
      payload = {}
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!(parse_passed_options(options))
      else
        payload.deep_merge!(parse_passed_options(options))
        # raise_command_error "Specify at least one option to update.\n#{optparse}" if payload.empty?
      end
      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to apply this app: #{app['name']}?")
        return 9, "aborted command"
      end
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.apply(app["id"], params, payload)
        return
      end
      json_response = @apps_interface.apply(app["id"], params, payload)
      render_result = render_with_format(json_response, options)
      return 0 if render_result
      print_green_success "Applied app #{app['name']}"
      #return get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      return 0
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

  def cancel_removal(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      build_common_options(opts, options, [:json, :dry_run, :quiet, :remote])
    end
    optparse.parse!(args)
    if args.count < 1
      puts optparse
      exit 1
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.cancel_removal(app['id'])
        return
      end
      json_response = @apps_interface.cancel_removal(app['id'])
      if options[:json]
        print as_json(json_response, options), "\n"
        return
      elsif !options[:quiet]
        get([app['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
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
      # opts.on('--hosts HOSTS', String, "Filter logs to specific Host ID(s)") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--servers HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--vms HOSTS', String, "alias for --hosts") do |val|
      #   params['servers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      # opts.on('--container CONTAINER', String, "Filter logs to specific Container ID(s)") do |val|
      #   params['containers'] = val.to_s.split(",").collect {|it| it.to_s.strip }.select {|it| it }.compact
      # end
      opts.on( '-n', '--node NODE_ID', "Scope logs to specific Container or VM" ) do |node_id|
        options[:node_id] = node_id.to_i
      end
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
      container_ids = []
      app['appTiers'].each do |app_tier|
        app_tier['appInstances'].each do |app_instance|
          container_ids += app_instance['instance']['containers']
        end if app_tier['appInstances']
      end if app['appTiers']
      if container_ids.empty?
        print cyan,"app is empty",reset,"\n"
        return 0
        # print_error yellow,"app is empty",reset,"\n"
        # return 1
      end

      if options[:node_id]
        if container_ids.include?(options[:node_id])
          container_ids = [options[:node_id]]
        else
          print_red_alert "App does not include node #{options[:node_id]}"
          return 1
        end
      end
      params = {}
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

      title = "App Logs: #{app['name']}"
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
      print reset,"\n"
      return 0
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
      # params['query'] = params.delete('phrase') if params['phrase']
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

  def view(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app]")
      opts.on('-w','--wiki', "Open the wiki tab for this app") do
        options[:link_tab] = "wiki"
      end
      opts.on('--tab VALUE', String, "Open a specific tab") do |val|
        options[:link_tab] = val.to_s
      end
      build_common_options(opts, options, [:dry_run, :remote])
      opts.footer = "View an app in a web browser" + "\n" +
                    "[app] is required. This is the name or id of an app. Supports 1-N [app] arguments."
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
      app = find_app_by_name_or_id(arg)
      return 1 if app.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/apps/#{app['id']}"
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
      opts.banner = subcommand_usage("[app]")
      opts.on('--view', '--view', "View wiki page in web browser.") do
        open_wiki_link = true
      end
      build_common_options(opts, options, [:json, :dry_run, :remote])
      opts.footer = "View wiki page details for an app." + "\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      puts_error  "#{Morpheus::Terminal.angry_prompt}wrong number of arguments. Expected 1 and received #{args.count} #{args.inspect}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?


      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.wiki(app["id"], params)
        return
      end
      json_response = @apps_interface.wiki(app["id"], params)
      page = json_response['page']
  
      render_result = render_with_format(json_response, options, 'page')
      return 0 if render_result

      if page

        # my_terminal.exec("wiki get #{page['id']}")

        print_h1 "App Wiki Page: #{app['name']}"
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
      opts.footer = "View app wiki page in a web browser" + "\n" +
                    "[app] is required. This is the name or id of an app."
    end
    optparse.parse!(args)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?

      link = "#{@appliance_url}/login/oauth-redirect?access_token=#{@access_token}\\&redirectUri=/provisioning/apps/#{app['id']}#!wiki"

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
      opts.banner = subcommand_usage("[app] [options]")
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
      app = find_app_by_name_or_id(args[0])
      return 1 if app.nil?
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
      @apps_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @apps_interface.dry.update_wiki(app["id"], payload)
        return
      end
      json_response = @apps_interface.update_wiki(app["id"], payload)

      if options[:json]
        puts as_json(json_response, options)
      else
        print_green_success "Updated wiki page for app #{app['name']}"
        wiki([app['id']])
      end
      return 0
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

  def print_apps_table(apps, options={})
    
    table_color = options[:color] || cyan
    rows = apps.collect do |app|
      tiers_str = format_app_tiers(app)
      instances_str = (app['instanceCount'].to_i == 1) ? "1" : "#{app['instanceCount']}"
      containers_str = (app['containerCount'].to_i == 1) ? "1" : "#{app['containerCount']}"
      stats = app['stats']
      # app_stats = app['appStats']
      cpu_usage_str = !stats ? "" : generate_usage_bar((stats['cpuUsage'] || stats['cpuUsagePeak']).to_f, 100, {max_bars: 10})
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
      {
        id: app['id'],
        name: app['name'],
        description: app['description'],
        blueprint: app['blueprint'] ? app['blueprint']['name'] : '',
        type: app['type'] ? format_blueprint_type(app['type']) : (format_blueprint_type(app['blueprint'] ? app['blueprint']['type'] : nil)),
        group: app['group'] ? app['group']['name'] : app['siteId'],
        environment: app['appContext'],
        tiers: tiers_str,
        instances: instances_str,
        containers: containers_str,
        owner: app['owner'] ? app['owner']['username'] : '',
        tenant: app['account'] ? app['account']['name'] : nil,
        status: format_app_status(app, table_color),
        cpu: cpu_usage_str + cyan,
        memory: memory_usage_str + table_color,
        storage: storage_usage_str + table_color,
        created: format_local_dt(app['dateCreated']),
        updated: format_local_dt(app['lastUpdated'])
      }
    end

    columns = [
      :id,
      :name,
      # :description,
      :type,
      :blueprint,
      :group,
      :environment,
      :status,
      :tiers,
      :instances,
      :containers,
      {:cpu => {:display_name => "MAX CPU"} },
      :memory,
      :storage,
      :owner,
      #:tenant,
      :created,
      :updated
    ]
    
    # custom pretty table columns ...
    # if options[:include_fields]
    #   columns = options[:include_fields]
    # end
    # print cyan
    print as_pretty_table(rows, columns, options) #{color: table_color}
    print reset
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

  def update_wiki_page_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'displayOrder' => 1, 'description' => 'The name of the wiki page for this instance. Default is the instance name.'},
      #{'fieldName' => 'category', 'fieldLabel' => 'Category', 'type' => 'text', 'required' => false, 'displayOrder' => 2},
      {'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => false, 'displayOrder' => 3, 'description' => 'The content (markdown) of the wiki page.'}
    ]
  end
end
