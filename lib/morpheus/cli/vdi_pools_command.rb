require 'morpheus/cli/cli_command'

# CLI command VDI Pool management
# UI is Tools: VDI Pools
# API is /vdi-pools and returns vdiPools
class Morpheus::Cli::VdiPoolsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::VdiHelper
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'vdi-pools'
  set_command_description "View and manage VDI pools"

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @vdi_pools_interface = @api_client.vdi_pools
    @vdi_apps_interface = @api_client.vdi_apps
    @vdi_gateways_interface = @api_client.vdi_gateways
    @option_types_interface = @api_client.option_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on( '--enabled [on|off]', String, "Filter by enabled" ) do |val|
        params['enabled'] = (val.to_s != 'false' && val.to_s != 'off')
      end
      build_standard_list_options(opts, options)
      opts.footer = "List VDI pools."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @vdi_pools_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_pools_interface.dry.list(params)
      return
    end
    json_response = @vdi_pools_interface.list(params)
    render_response(json_response, options, vdi_pool_list_key) do
      vdi_pools = json_response[vdi_pool_list_key]
      print_h1 "Morpheus VDI Pools", parse_list_subtitles(options), options
      if vdi_pools.empty?
        print cyan,"No VDI pools found.",reset,"\n"
      else
        print as_pretty_table(vdi_pools, vdi_pool_list_column_definitions.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[pool]")
      opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
        options[:show_config] = true
      end
      opts.on('--no-config', "Do not display Config YAML." ) do
        options[:no_config] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific VDI pool.
[pool] is required. This is the name or id of a VDI pool.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get(arg, params, options)
    end
  end

  def _get(id, params, options)
    vdi_pool = nil
    if id.to_s !~ /\A\d{1,}\Z/
      vdi_pool = find_vdi_pool_by_name(id)
      return 1, "VDI pool not found for #{id}" if vdi_pool.nil?
      id = vdi_pool['id']
    end
    @vdi_pools_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_pools_interface.dry.get(id, params)
      return
    end
    json_response = @vdi_pools_interface.get(id, params)
    vdi_pool = json_response[vdi_pool_object_key]
    config = vdi_pool['config'] || {}
    # export just the config as json or yaml (default)
    if options[:show_config]
      unless options[:json] || options[:yaml] || options[:csv]
        options[:yaml] = true
      end
      return render_with_format(config, options)
    end
    render_response(json_response, options, vdi_pool_object_key) do
      print_h1 "VDI Pool Details", [], options
      print cyan
      show_columns = vdi_pool_column_definitions
      show_columns.delete("VDI Apps") unless vdi_pool['apps']
      show_columns.delete("VDI Gateway") unless vdi_pool['gateway']
      show_columns.delete("Guest Console Jump Host") unless vdi_pool['guestConsoleJumpHost']
      show_columns.delete("Guest Console Jump Port") unless vdi_pool['guestConsoleJumpPort']
      show_columns.delete("Guest Console Jump Username") unless vdi_pool['guestConsoleJumpUsername']
      show_columns.delete("Guest Console Jump Password") unless vdi_pool['guestConsoleJumpPassword']
      show_columns.delete("Guest Console Jump Keypair") unless vdi_pool['guestConsoleJumpKeypair']
      print_description_list(show_columns, vdi_pool)

      if vdi_pool['allocations'] && vdi_pool['allocations'].size > 0
        print_h2 "Allocations"
        opt_columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"USER" => lambda {|it| it['user'] ? it['user']['username'] : nil } },
          {"STATUS" => lambda {|it| format_vdi_allocation_status(it) } },
          {"CREATED" => lambda {|it| format_local_dt it['dateCreated'] } },
          {"RELEASE DATE" => lambda {|it| format_local_dt it['releaseDate'] } },
        ]
        print as_pretty_table(vdi_pool['allocations'], opt_columns)
      else
        # print cyan,"No option types found for this VDI pool.","\n",reset
      end

      if options[:no_config] != true
        print_h2 "Config YAML"
        if config
          #print reset,(JSON.pretty_generate(config) rescue config),"\n",reset
          #print reset,(as_yaml(config, options) rescue config),"\n",reset
          config_string = as_yaml(config, options) rescue config
          config_lines = config_string.split("\n")
          config_line_count = config_lines.size
          max_lines = 10
          if config_lines.size > max_lines
            config_string = config_lines.first(max_lines).join("\n")
            config_string << "\n\n"
            config_string << "#{dark}(#{(config_line_count - max_lines)} more lines were not shown, use -c to show the config)#{reset}"
            #config_string << "\n"
          end
          # strip --- yaml header
          if config_string[0..3] == "---\n"
            config_string = config_string[4..-1]
          end
          print reset,config_string.chomp("\n"),"\n",reset
        else
          print reset,"(blank)","\n",reset
        end
      
      end

      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_vdi_pool_option_types)
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      opts.on( '-i', '--interactive', "Interactive Config, prompt for each input of the instance configuration" ) do
        options[:interactive_config] = true
      end
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new VDI pool.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    if options[:options]['logo']
      options[:options]['iconPath'] = 'custom'
    end
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_pool_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # prompt for option types
      # skip config if using interactive prompt
      filtered_option_types = add_vdi_pool_option_types
      if options[:interactive_config] || options[:options]['instanceConfig']
        filtered_option_types = filtered_option_types.reject {|it| it['fieldName'] == 'config' }
      end
      v_prompt = Morpheus::Cli::OptionTypes.prompt(filtered_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # logo upload requires multipart instead of json
      if params['logo']
        params['logo'] = File.new(params['logo'], 'rb')
        payload[:multipart] = true
      end
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
        end
      end
      # pass instanceConfig: "{...}" instead of config: {} to preserve config order...
      if params['config']
        config_map = params.delete('config')
        params['instanceConfig'] = as_json(config_map, {:pretty_json => true})
      end
      if options[:interactive_config]
        print_h2 "Instance Config"
        config_map = prompt_vdi_config(options)
        params['config'] = config_map
      end
      # massage association params a bit
      params['gateway'] = {'id' => params['gateway']}  if params['gateway'] && !params['gateway'].is_a?(Hash)
      # params['apps'] = ...
      payload.deep_merge!({vdi_pool_object_key => params})
    end
    @vdi_pools_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_pools_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @vdi_pools_interface.create(payload)
    vdi_pool = json_response[vdi_pool_object_key]
    render_response(json_response, options, vdi_pool_object_key) do
      print_green_success "Added VDI pool #{vdi_pool['name']}"
      return _get(vdi_pool["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[pool] [options]")
      build_option_type_options(opts, options, update_vdi_pool_option_types)
      opts.on('--config-file FILE', String, "Config from a local JSON or YAML file") do |val|
        options[:config_file] = val.to_s
        file_content = nil
        full_filename = File.expand_path(options[:config_file])
        if File.exists?(full_filename)
          file_content = File.read(full_filename)
        else
          print_red_alert "File not found: #{full_filename}"
          return 1
        end
        parse_result = parse_json_or_yaml(file_content)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
          options[:options]['config'] = params['config'] # or file_content
        end
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a VDI pool.
[pool] is required. This is the name or id of a VDI pool.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    if options[:options]['logo']
      options[:options]['iconPath'] = 'custom'
    end
    connect(options)
    vdi_pool = find_vdi_pool_by_name_or_id(args[0])
    return 1 if vdi_pool.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_pool_object_key => parse_passed_options(options)})
    else
      params.deep_merge!(parse_passed_options(options))
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_vdi_pool_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # logo upload requires multipart instead of json
      if params['logo']
        params['logo'] = File.new(params['logo'], 'rb')
        payload[:multipart] = true
      end
      # convert config string to a map
      config = params['config']
      if config && config.is_a?(String)
        parse_result = parse_json_or_yaml(config)
        config_map = parse_result[:data]
        if config_map.nil?
          # todo: bubble up JSON.parse error message
          raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
          #raise_command_error "Failed to parse config as valid YAML or JSON."
        else
          params['config'] = config_map
        end
      end
      # pass instanceConfig: "{...}" instead of config: {} to preserve config order...
      if params['config']
        config_map = params.delete('config')
        params['instanceConfig'] = as_json(config_map, {:pretty_json => true})
      end
      # massage association params a bit
      params['gateway'] = {'id' => params['gateway']}  if params['gateway'] && !params['gateway'].is_a?(Hash)
      # params['apps'] = ...
      payload.deep_merge!({vdi_pool_object_key => params})
      if payload[vdi_pool_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @vdi_pools_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_pools_interface.dry.update(vdi_pool['id'], payload)
      return
    end
    json_response = @vdi_pools_interface.update(vdi_pool['id'], payload)
    vdi_pool = json_response[vdi_pool_object_key]
    render_response(json_response, options, vdi_pool_object_key) do
      print_green_success "Updated VDI pool #{vdi_pool['name']}"
      return _get(vdi_pool["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[pool] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a VDI pool.
[pool] is required. This is the name or id of a VDI pool.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    vdi_pool = find_vdi_pool_by_name_or_id(args[0])
    return 1 if vdi_pool.nil?
    @vdi_pools_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_pools_interface.dry.destroy(vdi_pool['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the VDI pool #{vdi_pool['name']}?")
      return 9, "aborted command"
    end
    json_response = @vdi_pools_interface.destroy(vdi_pool['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed VDI pool #{vdi_pool['name']}"
    end
    return 0, nil
  end

  private
  
  def vdi_pool_list_column_definitions()

    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Persistent" => lambda {|it| format_boolean(it['persistentUser']) },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Pool Usage" => lambda {|it| 
        # todo: [==      ]  2/8 would be neat generate_usage_bar(...)
        
        # used_value = it['reservedCount'] ? format_number(it['reservedCount']) : "N/A"
        # max_value = it['maxPoolSize'] ? format_number(it['maxPoolSize']) : "N/A"
        used_value = it['usedCount']
        max_value = it['maxPoolSize']
        usage_bar = generate_usage_bar(used_value, max_value, {:bar_color => cyan, :max_bars => 10, :percent_sigdig => 0})
        usage_label = "#{used_value} / #{max_value}"
        usage_bar + cyan + " " + "(" + usage_label + ")"
      },
      # Status will always show AVAILABLE right now, so that's weird..
      # "Status" => lambda {|it| format_vdi_pool_status(it) },
    }
  end

  def vdi_pool_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Owner" => lambda {|it| it['owner'] ? it['owner']['username'] || it['owner']['name'] : (it['user'] ? it['user']['username'] || it['user']['name'] : nil) },
      "Min Idle" => lambda {|it| format_number(it['minIdle']) rescue '' },
      "Initial Pool Size" => lambda {|it| format_number(it['initialPoolSize']) rescue '' },
      "Max Idle" => lambda {|it| format_number(it['maxIdle']) rescue '' },
      "Max Size" => lambda {|it| format_number(it['maxPoolSize']) rescue '' },
      "Lease Timeout" => lambda {|it| format_number(it['allocationTimeoutMinutes']) rescue '' },
      "Persistent" => lambda {|it| format_boolean(it['persistentUser']) },
      "Allow Copy" => lambda {|it| format_boolean(it['allowCopy']) },
      "Allow Printer" => lambda {|it| format_boolean(it['allowPrinter']) },
      "Allow File Share" => lambda {|it| format_boolean(it['allowFileshare']) },
      "Allow Hypervisor Console" => lambda {|it| format_boolean(it['allowHypervisorConsole']) },
      "Auto Create User" => lambda {|it| format_boolean(it['autoCreateLocalUserOnReservation']) },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Logo" => lambda {|it| it['logo'] || it['imagePath'] },
      #"Config" => lambda {|it| it['config'] },
      "Group" => lambda {|it| it['group'] ? it['group']['name'] : nil },
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : nil },
      "VDI Apps" => lambda {|it| it['apps'] ? it['apps'].collect {|vdi_app| vdi_app['name'] }.join(', ') : nil },
      "VDI Gateway" => lambda {|it| it['gateway'] ? it['gateway']['name'] : nil },
      "Guest Console Jump Host" => lambda {|it| it['guestConsoleJumpHost'] },
      "Guest Console Jump Port" => lambda {|it| it['guestConsoleJumpPort'] },
      "Guest Console Jump Username" => lambda {|it| it['guestConsoleJumpUsername'] },
      "Guest Console Jump Password" => lambda {|it| it['guestConsoleJumpPassword'] },
      "Guest Console Jump Keypair" => lambda {|it| it['guestConsoleJumpKeypair'] ? it['guestConsoleJumpKeypair']['name'] : nil },
      "Idle Count" => lambda {|it| format_number(it['idleCount']) rescue '' },
      "Reserved Count" => lambda {|it| format_number(it['reservedCount']) rescue '' },
      "Preparing Count" => lambda {|it| format_number(it['preparingCount']) rescue '' },
      # "Status" => lambda {|it| format_vdi_pool_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_vdi_pool_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Choose a unique name for the VDI Pool'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description'},
      {'fieldName' => 'owner', 'fieldLabel' => 'Owner', 'type' => 'select', 'optionSource' => 'users'},
      {'fieldName' => 'minIdle', 'fieldLabel' => 'Min Idle', 'type' => 'number', 'defaultValue' => '0', 'description' => 'Sets the minimum number of idle instances on standby in the pool. The pool will always try to maintain this number of available instances on standby.'},
      {'fieldName' => 'initialPoolSize', 'fieldLabel' => 'Initial Pool Size', 'type' => 'number', 'defaultValue' => '0', 'description' => 'The initial size of the pool to be allocated on creation.'},
      {'fieldName' => 'maxIdle', 'fieldLabel' => 'Max Idle', 'type' => 'number', 'defaultValue' => '0', 'description' => 'Sets the maximum number of idle instances on standby in the pool. If the number of idle instances supersedes this, the pool will start removing instances.'},
      {'fieldName' => 'maxPoolSize', 'fieldLabel' => 'Max Size', 'type' => 'number', 'required' => true, 'description' => 'Max limit on number of allocations and instances within the pool.'},
      {'fieldName' => 'allocationTimeoutMinutes', 'fieldLabel' => 'Lease Timeout', 'type' => 'number', 'description' => 'Time (in minutes) after a user disconnects before an allocation is recycled or shutdown depending on persistence.'},
      {'fieldName' => 'persistentUser', 'fieldLabel' => 'Persistent', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'allowCopy', 'fieldLabel' => 'Allow Copy', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'allowPrinter', 'fieldLabel' => 'Allow Printer', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'allowFileshare', 'fieldLabel' => 'Allow File Share', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'allowHypervisorConsole', 'fieldLabel' => 'Allow Hypervisor Console', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'autoCreateLocalUserOnReservation', 'fieldLabel' => 'Auto Create User', 'type' => 'checkbox', 'defaultValue' => false},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Enable the VDI Pool to make it available for allocation.'},
      #{'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => 'iconList', 'defaultValue' => 'resource'},
      # iconList does not include custom, so add it ourselves..
      # only prompt for logo file if custom
      {'code' => 'vdiPool.iconPath', 'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        dropdown = api_client.options.options_for_source("iconList")['data']
        if !dropdown.find {|it| it['value'] == 'custom'}
          dropdown.push({'name' => 'Custom', 'value' => 'custom'})
        end
        dropdown
      }, 'description' => 'Logo icon path or custom if uploading a custom logo', 'defaultValue' => 'resource'},
      {'dependsOnCode' => 'vdiPool.iconPath:custom', 'fieldName' => 'logo', 'fieldLabel' => 'Logo File', 'type' => 'file', 'required' => true, 'description' => 'Local filepath of image file to upload as custom icon'},
      # {'fieldName' => 'apps', 'fieldLabel' => 'VDI Apps', 'type' => 'multiSelect', 'description' => 'VDI Apps, comma separated list of names or IDs.'},
      # {'fieldName' => 'gateway', 'fieldLabel' => 'Gateway', 'type' => 'select', 'optionSource' => 'vdiGateways'},
      {'fieldName' => 'apps', 'fieldLabel' => 'VDI Apps', 'type' => 'multiSelect', 'optionSource' => lambda { |api_client, api_params| 
        api_client.vdi_apps.list({max:10000})[vdi_app_list_key].collect {|it| {'name' => it['name'], 'value' => it['id']} } 
      }, 'description' => 'VDI Apps, comma separated list of names or IDs.'},
      {'fieldName' => 'gateway', 'fieldLabel' => 'VDI Gateway', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params| 
        api_client.vdi_gateways.list({max:10000})[vdi_gateway_list_key].collect {|it| {'name' => it['name'], 'value' => it['id']} }
      }, 'description' => 'VDI Gateway'},
      {'fieldName' => 'config', 'fieldLabel' => 'Config', 'type' => 'code-editor', 'description' => 'JSON or YAML', 'required' => true},
      # todo:
      # Guest Console Jump Host
      # Guest Console Jump Port
      # Guest Console Jump Username
      # Guest Console Jump Password
      # Guest Console Jump Keypair
    ]
  end

  def update_vdi_pool_option_types
    list = add_vdi_pool_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  # finders are in VdiHelper mixin

  # prompt for an instance config (vdiPool.instanceConfig)
  def prompt_vdi_config(options)
    # use config if user passed one in..
    scope_context = 'instanceConfig'
    scoped_instance_config = {}
    if options[:options][scope_context].is_a?(Hash)
      scoped_instance_config = options[:options][scope_context]
    end

    # now configure an instance like normal, use the config as default options with :always_prompt
    instance_prompt_options = {}
    # instance_prompt_options[:group] = group ? group['id'] : nil
    # #instance_prompt_options[:cloud] = cloud ? cloud['name'] : nil
    # instance_prompt_options[:default_cloud] = cloud ? cloud['name'] : nil
    # instance_prompt_options[:environment] = selected_environment ? selected_environment['code'] : nil
    # instance_prompt_options[:default_security_groups] = scoped_instance_config['securityGroups'] ? scoped_instance_config['securityGroups'] : nil
    
    instance_prompt_options[:no_prompt] = options[:no_prompt]
    #instance_prompt_options[:always_prompt] = options[:no_prompt] != true # options[:always_prompt]
    instance_prompt_options[:options] = scoped_instance_config
    #instance_prompt_options[:options][:always_prompt] = instance_prompt_options[:no_prompt] != true
    instance_prompt_options[:options][:no_prompt] = instance_prompt_options[:no_prompt]
    
    #instance_prompt_options[:name_required] = true
    # instance_prompt_options[:instance_type_code] = instance_type_code
    # todo: an effort to render more useful help eg.  -O Web.0.instance.name
    help_field_prefix = scope_context
    instance_prompt_options[:help_field_prefix] = help_field_prefix
    instance_prompt_options[:options][:help_field_prefix] = help_field_prefix
    # instance_prompt_options[:locked_fields] = scoped_instance_config['lockedFields']
    # instance_prompt_options[:for_app] = true
    instance_prompt_options[:select_datastore] = true
    instance_prompt_options[:name_required] = true
    # this provisioning helper method handles all (most) of the parsing and prompting
    instance_config_payload = prompt_new_instance(instance_prompt_options)
    return instance_config_payload
  end
end
