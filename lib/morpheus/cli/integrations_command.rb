require 'morpheus/cli/cli_command'

class Morpheus::Cli::IntegrationsCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'integrations'
  set_command_description "Integrations: View and manage integrations"

  register_subcommands :list, :get, :add, :update, :remove, :refresh
  register_subcommands :list_objects, :get_object, :add_object, :remove_object
  register_subcommands :list_types, :get_type

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @integrations_interface = @api_client.integrations
    @integration_types_interface = @api_client.integration_types
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on('-t', '--type CODE', "Filter by type code(s), see `list-types` for available type codes") do |val|
        params['type'] = val
      end
      opts.on('--url URL', String, "Filter by url") do |val|
        params['url'] = val
      end
      build_standard_list_options(opts, options)
      opts.footer = "List integrations."
    end
    optparse.parse!(args)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    connect(options)
    params.merge!(parse_list_options(options))
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.list(params)
      return
    end
    json_response = @integrations_interface.list(params)
    render_response(json_response, options, integration_list_key) do
      integrations = json_response[integration_list_key]
      print_h1 "Morpheus Integrations", parse_list_subtitles(options), options
      if integrations.empty?
        print cyan,"No integrations found.",reset,"\n"
      else
        list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| format_integration_type(it) },
          "URL" => lambda {|it| it['url'] },
          "Username" => lambda {|it| it['username'] },
          "Enabled" => lambda {|it| format_boolean(it['enabled']) },
          "Status Date" => lambda {|it| format_local_dt(it['statusDate']) },
          "Status" => lambda {|it| format_integration_status(it) },
          # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
          # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        }.upcase_keys!
        print as_pretty_table(integrations, list_columns, options)
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
      opts.banner = subcommand_usage("[integration]")
      opts.on('--objects', 'Display exposed objects for the integration.') do
        options[:show_objects] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific integration.
[integration] is required. This is the name or id of an integration.
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
    integration = nil
    if id.to_s !~ /\A\d{1,}\Z/
      integration = find_integration_by_name_or_id(id)
      return 1, "integration not found for #{id}" if integration.nil?
      id = integration['id']
    end
    if options[:show_objects]
      params['objects'] = true
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.get(id, params)
      return
    end
    json_response = @integrations_interface.get(id, params)
    integration = json_response[integration_object_key]
    render_response(json_response, options, integration_object_key) do
      print_h1 "Integration Details", [], options
      print cyan
      show_columns = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| format_integration_type(it) },
        "URL" => lambda {|it| it['url'] },
        "Host" => lambda {|it| it['host'] },
        "Port" => lambda {|it| it['port'] },
        "Username" => lambda {|it| it['username'] },
        "Password" => lambda {|it| it['password'] },
        "Token" => lambda {|it| it['token'] },
        "Service Key" => lambda {|it| it['serviceKey'] ? it['serviceKey']['name'] : nil },
        "Auth Key" => lambda {|it| it['authKey'] ? it['authKey']['name'] : nil },
        "Enabled" => lambda {|it| format_boolean(it['enabled']) },
        "Status Date" => lambda {|it| format_local_dt(it['statusDate']) },
        "Status" => lambda {|it| format_integration_status(it) },
        # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      show_columns.delete("URL") if integration['url'].nil?
      show_columns.delete("Host") if integration['host'].nil?
      show_columns.delete("Port") if integration['port'].nil?
      show_columns.delete("Password") if integration['password'].nil?
      show_columns.delete("Token") if integration['token'].nil?
      show_columns.delete("Service Key") if integration['serviceKey'].nil?
      show_columns.delete("Auth Key") if integration['authKey'].nil?
      print_description_list(show_columns, integration, options)

      if options[:show_objects]
        # they are loaded above with ?objects=true
        integration_objects = integration['objects']
        if integration_objects.nil?
          objects_json_response = @integrations_interface.list_objects(integration['id'], {})
          integration_objects = objects_json_response[integration_object_list_key]
        end
        cloud_objects = integration_objects.select {|it| it['refType'] == "ComputeZone" }
        library_objects = integration_objects.select {|it| it['refType'] == "InstanceTypeLayout" || it['refType'] == "InstanceType" }
        blueprint_objects = integration_objects.select {|it| it['refType'] == "AppTemplate" }
        catalog_objects = integration_objects.select {|it| it['refType'] == "CatalogItemType" }
        if integration_objects.empty?
          print reset,"\n"
          print cyan,"No objects found.",reset,"\n"
        else
          # Exposed Clouds
          if !cloud_objects.empty?
            print_h2 "Exposed Clouds", [], options
            list_columns = {
              # "ID" => 'id',
              "Name" => 'name',
              # "Category" => 'category',
              # "Ref Type" => 'refType',
              # "Cloud ID" => 'refId',
              "Group" => lambda {|it| it['group']['name'] rescue nil },
            }.upcase_keys!
            print as_pretty_table(cloud_objects, list_columns, options)
          end

          # Exposed Libraries
          if !library_objects.empty?
            # print_h2 "Exposed Libraries", [], options
            print_h2 "Exposed Layouts", [], options
            list_columns = {
              # "ID" => 'id',
              "Name" => 'name',
              "Version" => lambda {|it| it['layout']['instanceVersion'] rescue nil },
              "Instance Type" => lambda {|it| it['layout']['instanceType']['name'] rescue nil },
              "Provision Type" => lambda {|it| it['layout']['provisionType']['name'] rescue nil },
            }.upcase_keys!
            print as_pretty_table(library_objects, list_columns, options)
          end

          # Exposed Blueprints
          if !blueprint_objects.empty?
            print_h2 "Exposed Blueprints", [], options
            list_columns = {
              # "ID" => 'id',
              "Name" => 'name',
              # "Type" => lambda {|it| it['blueprint']['type'] rescue nil },
              "Blueprint" => lambda {|it| it['blueprint']['name'] rescue nil },
              "Group" => lambda {|it| it['group']['name'] rescue nil },
            }.upcase_keys!
            print as_pretty_table(blueprint_objects, list_columns, options)
          end

          # Exposed Catalog Items
          if !catalog_objects.empty?
            print_h2 "Exposed Catalog Items", [], options
            list_columns = {
              # "ID" => 'id',
              "Name" => 'name',
            }.upcase_keys!
            print as_pretty_table(catalog_objects, list_columns, options)
          end
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
      opts.banner = subcommand_usage("[name] -t CODE [options]")
      # opts.on('-t', '--type CODE', "Integration Type code, see `#{command_name} list-types` for available type codes") do |val|
      #   options[:options]['type'] = val
      # end
      build_option_type_options(opts, options, add_integration_option_types)
      build_option_type_options(opts, options, add_integration_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new integration.
[name] is required. This is the name of the new integration
Configuration options vary by integration type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
      # Type prompt first
      #params['type'] = Morpheus::Cli::OptionTypes.no_prompt([{'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'selectOptions' => [{'name' => 'Instance', 'value' => 'instance'}, {'name' => 'Blueprint', 'value' => 'blueprint'}, {'name' => 'Workflow', 'value' => 'workflow'}], 'defaultValue' => 'instance', 'required' => true}], options[:options], @api_client, options[:params])['type']
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_integration_option_types(), options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_integration_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)

      # lookup type by name or code to validate it exists and to prompt for its optionTypes
      # set integration.type=code because the api expects it that way.
      if params['type'].to_s.empty?
        raise_command_error "missing required option: --type TYPE", args, optparse
      end
      integration_type = find_integration_type_by_name_or_code_id(params['type'])
      if integration_type.nil?
        return 1, "integration type not found for #{params['type']}"
      end
      params['type'] = integration_type['code']
      config_option_types = integration_type['optionTypes']
      if config_option_types.nil?
        config_option_types = @integration_types_interface.option_types(integration_type['id'])['optionTypes']
      end
      if config_option_types.nil?
        print yellow,"No option types found for integration type: #{integration_type['name']} (#{integration_type['code']})", reset, "\n"
      end
      if config_option_types && config_option_types.size > 0
        # optionTypes do not need fieldContext: 'integration'
        config_option_types.each do |opt|
          if opt['fieldContext'] == 'integration' || opt['fieldContext'] == 'domain'
            opt['fieldContext'] = nil
          end
        end
        config_prompt = Morpheus::Cli::OptionTypes.prompt(config_option_types, options[:options], @api_client, options[:params])
        config_prompt.deep_compact!
        params.deep_merge!(config_prompt)
      end
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      payload[integration_object_key].deep_merge!(params)
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @integrations_interface.create(payload)
    integration = json_response[integration_object_key]
    render_response(json_response, options, integration_object_key) do
      print_green_success "Added integration #{integration['name']}"
      return _get(integration["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [options]")
      build_option_type_options(opts, options, update_integration_option_types)
      build_option_type_options(opts, options, update_integration_advanced_option_types)
      opts.on(nil, '--no-refresh', "Skip refresh on update.") do
        params['refresh'] = 'false'
      end
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update an integration.
[integration] is required. This is the name or id of an integration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    integration = find_integration_by_name_or_id(args[0])
    return 1 if integration.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
      # do not prompt on update
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_integration_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_integration_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      # convert checkbox "on" and "off" to true and false
      params.booleanize!
      # massage association params a bit
      
      payload.deep_merge!({integration_object_key => params})
      if payload[integration_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.update(integration['id'], payload)
      return
    end
    json_response = @integrations_interface.update(integration['id'], payload)
    integration = json_response[integration_object_key]
    render_response(json_response, options, integration_object_key) do
      print_green_success "Updated integration #{integration['name']}"
      return _get(integration["id"], {}, options)
    end
    return 0, nil
  end

  def refresh(args)
    options = {}
    query_params = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [options]")
      build_option_type_options(opts, options, update_integration_option_types)
      build_option_type_options(opts, options, update_integration_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Refresh an integration.
[integration] is required. This is the name or id of an integration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    query_params.merge!(parse_query_options(options))
    integration = find_integration_by_name_or_id(args[0])
    return 1 if integration.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({integration_object_key => parse_passed_options(options)})
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.refresh(integration['id'], query_params, payload)
      return
    end
    json_response = @integrations_interface.refresh(integration['id'], query_params, payload)
    integration = json_response[integration_object_key]
    render_response(json_response, options, integration_object_key) do
      print_green_success "Refreshed integration #{integration['name']}"
      return _get(integration["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an integration.
[integration] is required. This is the name or id of an integration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    integration = find_integration_by_name_or_id(args[0])
    return 1 if integration.nil?
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.destroy(integration['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the integration #{integration['name']}?")
      return 9, "aborted command"
    end
    json_response = @integrations_interface.destroy(integration['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed integration #{integration['name']}"
    end
    return 0, nil
  end


  def list_types(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is false.") do |val|
        params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      end
      build_standard_list_options(opts, options)
      opts.footer = "List integration types."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @integration_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integration_types_interface.dry.list(params)
      return
    end
    json_response = @integration_types_interface.list(params)
    render_response(json_response, options, integration_type_list_key) do
      integration_types = json_response[integration_type_list_key]
      print_h1 "Morpheus Integration Types", parse_list_subtitles(options), options
      if integration_types.empty?
        print cyan,"No integration types found.",reset,"\n"
      else
        list_columns = integration_type_column_definitions.upcase_keys!
        print as_pretty_table(integration_types, list_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_type(args)
    params = {'optionTypes' => true}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[type]")
      build_standard_get_options(opts, options)
      opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is true.") do |val|
        params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      end
      opts.footer = <<-EOT
Get details about a specific integration type.
[type] is required. This is the name or id of an integration type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args)
    return run_command_for_each_arg(id_list) do |arg|
      _get_type(arg, params, options)
    end
  end

  def _get_type(id, params, options)
    integration_type = nil
    if id.to_s !~ /\A\d{1,}\Z/
      integration_type = find_integration_type_by_name_or_code(id)
      return 1, "integration type not found for name or code '#{id}'" if integration_type.nil?
      id = integration_type['id']
    end
    # /api/integration-types does not return optionTypes by default, use ?optionTypes=true
    @integration_types_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integration_types_interface.dry.get(id, params)
      return
    end
    json_response = @integration_types_interface.get(id, params)
    integration_type = json_response[integration_type_object_key]
    render_response(json_response, options, integration_type_object_key) do
      print_h1 "Integration Type Details", [], options
      print cyan
      show_columns = integration_type_column_definitions
      print_description_list(show_columns, integration_type)

      if integration_type['optionTypes'] && integration_type['optionTypes'].size > 0
        print_h2 "Option Types"
        opt_columns = [
          # {"ID" => lambda {|it| it['id'] } },
          {"FIELD NAME" => lambda {|it| (it['fieldContext'] && it['fieldContext'] != 'integration') ? [it['fieldContext'], it['fieldName']].join('.') : it['fieldName']  } },
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
          # {"DESCRIPTION" => lambda {|it| it['description'] }, # do it!
        ]
        print as_pretty_table(integration_type['optionTypes'], opt_columns)
      else
        # print cyan,"No option types found for this integration type.","\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  ## Integration Objects

  def list_objects(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [search]")
      opts.on('-t', '--type CODE', "Filter by types: cloud, layout, blueprint, catalog") do |val|
        params['type'] = [params['type'], val].compact.flatten.collect {|it| it.to_s.strip.split(",") }.flatten.collect {|it| it.to_s.strip }
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
List integration objects.
[integration] is required. This is the name or id of an integration.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)

    integration = find_integration_by_name_or_id(args[0])
    return 1, "integration not found for #{args[0]}" if integration.nil?

    if args.count > 1
      options[:phrase] = args[1..-1].join(" ")
    end
    params.merge!(parse_list_options(options))
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.list_objects(integration['id'], params)
      return 0, nil
    end
    json_response = @integrations_interface.list_objects(integration['id'], params)
    render_response(json_response, options, integration_list_key) do
      integration_objects = json_response[integration_object_list_key]
      print_h1 "Integration Objects [#{integration['name']}]", parse_list_subtitles(options), options
      if integration_objects.empty?
        print cyan,"No objects found.",reset,"\n"
      else
        list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          # "Category" => 'category',
          # "Ref Type" => 'refType',
          # "Ref ID" => 'refId',
          # "Type" => lambda {|it| it['type'] },
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          "Ref ID" => 'refId',
        }.upcase_keys!
        print as_pretty_table(integration_objects, list_columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end

  def get_object(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [object]")
      opts.on( '-c', '--config', "Display config only, for blueprint objects" ) do
        options[:show_config] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific integration object.
[integration] is required. This is the name or id of an integration.
[object] is required. This is the name or id of an integration object.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:2)
    connect(options)
    integration = find_integration_by_name_or_id(args[0])
    return 1, "integration not found for #{args[0]}" if integration.nil?
    params.merge!(parse_query_options(options))
    id_list = parse_id_list(args[1..-1])
    return run_command_for_each_arg(id_list) do |arg|
      _get_object(integration, arg, params, options)
    end
  end

  def _get_object(integration, id, params, options)
    integration_object = nil
    if id.to_s !~ /\A\d{1,}\Z/
      integration_object = find_integration_object_by_name_or_id(integration['id'], id)
      return 1, "integration object not found for #{id}" if integration_object.nil?
      id = integration_object['id']
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.get_object(integration['id'], id, params)
      return
    end
    json_response = @integrations_interface.get_object(integration['id'], id, params)
    integration_object = json_response[integration_object_object_key]
    config = integration_object['config']
    # export just the config as json (default) or yaml
    if options[:show_config]
      unless options[:json] || options[:yaml] || options[:csv]
        options[:json] = :true
      end
      return render_with_format(config, options)
    end
    render_response(json_response, options, integration_object_object_key) do
      print_h1 "Integration Object Details", [], options
      print cyan
      if integration_object['type'] == 'cloud'
        show_columns = {
          "Integration" => lambda {|it| integration['name'] },
          "Object ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          # "Cloud" => lambda {|it| it['cloud']['name'] rescue nil },
          # "Ref Type" => 'refType',
          "Ref ID" => 'refId',
          # "Reference" => lambda {|it| ("#{it['refType']}: #{it['refId']}" rescue nil) },
          "Group" => lambda {|it| it['group']['name'] rescue nil },
        }
        print_description_list(show_columns, integration_object, options)
        print reset,"\n"
      elsif integration_object['type'] == 'layout'
        show_columns = {
          "Integration" => lambda {|it| integration['name'] },
          "Object ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          # "Layout" => lambda {|it| it['layout']['name'] rescue nil },
          # "Ref Type" => 'refType',
          "Ref ID" => 'refId',
          # "Reference" => lambda {|it| ("#{it['refType']}: #{it['refId']}" rescue nil) },
          "Provision Type" => lambda {|it| it['layout']['provisionType']['name'] rescue nil },
          "Instance Type" => lambda {|it| it['layout']['instanceType']['name'] rescue nil },
          "Version" => lambda {|it| it['layout']['instanceVersion'] rescue nil },
        }
        print_description_list(show_columns, integration_object, options)
        print reset,"\n"
      elsif integration_object['type'] == 'blueprint'
        show_columns = {
          "Integration" => lambda {|it| integration['name'] },
          "Object ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          # "Ref Type" => 'refType',
          "Ref ID" => 'refId',
          # "Reference" => lambda {|it| ("#{it['refType']}: #{it['refId']}" rescue nil) },
          # "Blueprint Type" => lambda {|it| it['blueprint']['type'] rescue nil },
          "Blueprint" => lambda {|it| it['blueprint']['name'] rescue nil },
          "Group" => lambda {|it| it['group']['name'] rescue nil },
          "Default Cloud" => lambda {|it| it['defaultCloud']['name'] rescue nil },
          "Environment" => lambda {|it| it['environment'] rescue nil },
        }
        print_description_list(show_columns, integration_object, options)
        # print reset,"\n"
        # print_h2 "App Spec"
        print_h2 "Config"
        if config
          # config_string = integration_object['config'] || ""
          config_string = config.is_a?(Hash) ? JSON.pretty_generate(config) : config.to_s
          #print reset,config_string,"\n",reset
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
        print reset,"\n"
      elsif integration_object['type'] == 'catalog'
        show_columns = {
          "Integration" => lambda {|it| integration['name'] },
          "Object ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          "Catalog Item" => lambda {|it| it['catalogItemType']['name'] rescue nil },
          # "Ref Type" => 'refType',
          # "Ref ID" => 'refId',
          # "Reference" => lambda {|it| ("#{it['refType']}: #{it['refId']}" rescue nil) },
        }
        print_description_list(show_columns, integration_object, options)
        print reset,"\n"
      else
        # Unknown type?
        show_columns = {
          "Integration" => lambda {|it| integration['name'] },
          "Object ID" => 'id',
          "Name" => 'name',
          "Type" => lambda {|it| it['type'].to_s.capitalize },
          "Ref Type" => 'refType',
          "Ref ID" => 'refId',
        }
        print_description_list(show_columns, integration_object, options)
        print reset,"\n"
      end
    end
    return 0, nil
  end

  def add_object(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [name] -t CODE [options]")
      # opts.on('-t', '--type CODE', "Integration ObjectType code, see `#{command_name} list-types` for available type codes") do |val|
      #   options[:options]['type'] = val
      # end
      build_option_type_options(opts, options, add_integration_object_option_types)
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
      # build_option_type_options(opts, options, add_integration_object_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new integration object.
[integration] is required. This is the name or id of an integration.
[name] is required. This is the name of the new integration
Configuration options vary by integration type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1, max:2)
    options[:options]['name'] = args[1] if args[1]
    connect(options)
    integration = find_integration_by_name_or_id(args[0])
    return 1, "integration not found for #{args[0]}" if integration.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({integration_object_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({integration_object_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_integration_object_option_types(), options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      advanced_config = Morpheus::Cli::OptionTypes.no_prompt(add_integration_object_advanced_option_types, options[:options], @api_client, options[:params])
      advanced_config.deep_compact!
      params.deep_merge!(advanced_config)
      params.booleanize!

      # convert config string to a map
      # config = params['config']
      # if config && config.is_a?(String)
      #   parse_result = parse_json_or_yaml(config)
      #   config_map = parse_result[:data]
      #   if config_map.nil?
      #     # todo: bubble up JSON.parse error message
      #     raise_command_error "Failed to parse config as YAML or JSON. Error: #{parse_result[:err]}"
      #     #raise_command_error "Failed to parse config as valid YAML or JSON."
      #   else
      #     params['config'] = config_map
      #   end
      # end
      # if params['config']
      #   config_map = params.delete('config')
      #   params['config'] = as_json(config_map, {:pretty_json => true})
      # end
      # if options[:interactive_config]
      #   print_h2 "App Config"
      #   config_map = prompt_app_config(options)
      #   params['config'] = config_map
      # end

      payload[integration_object_object_key].deep_merge!(params)
    end
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.create_object(integration['id'], payload)
      return 0, nil
    end
    json_response = @integrations_interface.create_object(integration['id'], payload)
    integration_object = json_response[integration_object_object_key]
    render_response(json_response, options, integration_object_object_key) do
      print_green_success "Added integration_object #{integration_object['name']}"
      return _get_object(integration, integration_object["id"], {}, options)
    end
    return 0, nil
  end

#   def update_object(args)
#     options = {}
#     params = {}
#     optparse = Morpheus::Cli::OptionParser.new do |opts|
#       opts.banner = subcommand_usage("[integration] [object] [options]")
#       build_option_type_options(opts, options, update_integration_option_types)
#       build_option_type_options(opts, options, update_integration_advanced_option_types)
#       build_standard_update_options(opts, options)
#       opts.footer = <<-EOT
# Update an integration.
# [integration] is required. This is the name or id of an integration.
# [object] is required. This is the name or id of an integration object.
# EOT
#     end
#     optparse.parse!(args)
#     verify_args!(args:args, optparse:optparse, count:2)
#     connect(options)
#     integration = find_integration_by_name_or_id(args[0])
#     return 1, "integration not found for #{args[0]}" if integration.nil?
#     integration_object = find_integration_object_by_name_or_id(integration['id'], args[1])
#     return 1, "integration object not found for #{args[1]}" if integration_object.nil?
#     payload = {}
#     if options[:payload]
#       payload = options[:payload]
#       payload.deep_merge!({integration_object_object_key => parse_passed_options(options)})
#     else
#       payload.deep_merge!({integration_object_object_key => parse_passed_options(options)})
#       # do not prompt on update
#       v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_integration_object_option_types, options[:options], @api_client, options[:params])
#       v_prompt.deep_compact!
#       params.deep_merge!(v_prompt)
#       advanced_config = Morpheus::Cli::OptionTypes.no_prompt(update_integration_object_advanced_option_types, options[:options], @api_client, options[:params])
#       advanced_config.deep_compact!
#       params.deep_merge!(advanced_config)
#       # convert checkbox "on" and "off" to true and false
#       params.booleanize!
#       # massage association params a bit
      
#       payload.deep_merge!({integration_object_object_key => params})
#       if payload[integration_object_object_key].empty? # || options[:no_prompt]
#         raise_command_error "Specify at least one option to update.\n#{optparse}"
#       end
#     end
#     @integrations_interface.setopts(options)
#     if options[:dry_run]
#       print_dry_run @integrations_interface.dry.update_object(integration['id'], integration_object['id'], payload)
#       return
#     end
#     json_response = @integrations_interface.update_object(integration['id'], integration_object['id'], payload)
#     integration_object = json_response[integration_object_object_key]
#     render_response(json_response, options, integration_object_object_key) do
#       print_green_success "Updated integration object #{integration_object['name']}"
#       return _get_object(integration, integration_object["id"], {}, options)
#     end
#     return 0, nil
#   end

  def remove_object(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[integration] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete an integration object.
[integration] is required. This is the name or id of an integration.
[object] is required. This is the name or id of an integration object.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)
    integration = find_integration_by_name_or_id(args[0])
    return 1, "integration not found for #{args[0]}" if integration.nil?
    integration_object = find_integration_object_by_name_or_id(integration['id'], args[1])
    return 1, "integration object not found for #{args[1]}" if integration_object.nil?
    params.merge!(parse_query_options(options))
    @integrations_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @integrations_interface.dry.destroy_object(integration['id'], integration_object['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the integration object #{integration_object['name']}?")
      return 9, "aborted command"
    end
    json_response = @integrations_interface.destroy_object(integration['id'], integration_object['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed integration object #{integration_object['name']}"
    end
    return 0, nil
  end

  private

  def format_integration_type(integration)
    (integration['integrationType']['name'] || integration['integrationType']['code']) rescue integration['integrationType'].to_s
  end

  def add_integration_option_types
    [
      {'code' => 'integration.type', 'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => lambda { |api_client, api_params|
        # @integration_types_interface.list(max:-1)[integration_list_key].collect {|it|
        get_available_integration_types().collect {|it|
          {'name' => it['name'], 'value' => it['code']}
        } }, 'required' => true, 'description' => "Integration Type code, see `#{command_name} list-types` for available type codes"},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name of the integration'},
      # {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => true, 'description' => 'Can be used to disable an integration'}
    ]
  end

  def add_integration_advanced_option_types
    []
  end

  def update_integration_option_types
    list = add_integration_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def update_integration_advanced_option_types
    add_integration_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def integration_object_key
    'integration'
  end

  def integration_list_key
    'integrations'
  end

  def find_integration_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_integration_by_id(val)
    else
      return find_integration_by_name(val)
    end
  end

  def find_integration_by_id(id)
    begin
      json_response = @integrations_interface.get(id.to_i)
      return json_response[integration_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "integration not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_integration_by_name(name)
    json_response = @integrations_interface.list({name: name.to_s})
    integrations = json_response[integration_list_key]
    if integrations.empty?
      print_red_alert "integration not found by name '#{name}'"
      return nil
    elsif integrations.size > 1
      print_red_alert "#{integrations.size} integrations found by name '#{name}'"
      puts_error as_pretty_table(integrations, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return integrations[0]
    end
  end

  def format_integration_status(integration, return_color=cyan)
    out = ""
    status_string = integration['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    # elsif integration['enabled'] == false
    #   out << "#{red}DISABLED#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error' || status_string == 'offline'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{integration['statusMessage'] ? "#{return_color} - #{integration['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end


  def integration_type_column_definitions()
    {
      "ID" => 'id',
      "Code" => 'code',
      "Name" => 'name',
      # "Description" => 'description',
      "Category" => 'category',
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
    }
  end

  def integration_type_object_key
    'integrationType'
  end

  def integration_type_list_key
    'integrationTypes'
  end

  def find_integration_type_by_name_or_code_id(val, params={})
    if val.to_s =~ /\A\d{1,}\Z/
      return find_integration_type_by_id(val, params)
    else
      return find_integration_type_by_name_or_code(val)
    end
  end

  def find_integration_type_by_id(id, params={})
    begin
      json_response = @integration_types_interface.get(id.to_i, params)
      return json_response[integration_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "integration not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_integration_type_by_name(name, params={})
    json_response = @integration_types_interface.list(params.merge({name: name.to_s}))
    integration_types = json_response[integration_type_list_key]
    if integration_types.empty?
      print_red_alert "integration type not found by name '#{name}'"
      return nil
    elsif integration_types.size > 1
      print_red_alert "#{integration_types.size} integration types found by name '#{name}'"
      puts_error as_pretty_table(integration_types, [:id, :code, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return integration_types[0]
    end
  end

  def get_available_integration_types(refresh=false)
    if !@available_integration_types || refresh
      @available_integration_types = @integration_types_interface.list(max:10000)[integration_type_list_key]
    end
    return @available_integration_types
  end
  
  def find_integration_type_by_name_or_code(name)
    records = get_available_integration_types()
    record = records.find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
    record = record ? record : records.find { |z| z['id'].to_s == name.to_s }
    if record
      return record
    else
      print_red_alert "integration type not found by '#{name}'"
      return nil
    end
  end

  ## Integration Object helpers

  def add_integration_object_option_types
    [
      {'code' => 'integrationObject.type', 'shorthand' => '-t', 'switch' => 'type', 'fieldName' => 'type', 'fieldLabel' => 'Type', 'type' => 'select', 'optionSource' => 'integrationObjectTypes', 'required' => true, 'description' => "Integration Object Type eg. cloud, layout, blueprint, catalog", 'displayOrder' => 1},
      # {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => false, 'description' => 'Display Name of the integration object, default is the name of the referenced object', 'displayOrder' => 2},
      {'dependsOnCode' => 'integrationObject.type:cloud', 'switch' => 'group', 'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'optionSource' => 'groups', 'required' => true, 'description' => 'Group', 'displayOrder' => 3},
      {'dependsOnCode' => 'integrationObject.type:cloud', 'switch' => 'cloud', 'fieldName' => 'cloud', 'fieldLabel' => 'Cloud', 'type' => 'select', 'optionSource' => 'clouds', 'required' => true, 'description' => 'Cloud', 'displayOrder' => 4},
      {'dependsOnCode' => 'integrationObject.type:layout', 'switch' => 'technology', 'fieldName' => 'provisionType', 'fieldLabel' => 'Provision Type', 'type' => 'select', 'optionSource' => 'provisionTypes', 'required' => true, 'description' => 'Provision Type (Technology)', 'displayOrder' => 5},
      {'dependsOnCode' => 'integrationObject.type:layout', 'switch' => 'layout', 'fieldName' => 'layout', 'fieldLabel' => 'Layout', 'type' => 'typeahead', 'optionSource' => 'layouts', 'required' => true, 'description' => 'Layout', 'displayOrder' => 6},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'fieldName' => 'name', 'fieldLabel' => 'Catalog Item Name', 'type' => 'text', 'required' => true, 'description' => 'Display Name of the integration object', 'displayOrder' => 7},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'switch' => 'blueprint', 'fieldName' => 'blueprint', 'fieldLabel' => 'Blueprint', 'type' => 'select', 'optionSource' => 'blueprints', 'required' => true, 'description' => 'Blueprint', 'displayOrder' => 8, 'noParams' => true},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'switch' => 'group', 'fieldName' => 'group', 'fieldLabel' => 'Group', 'type' => 'select', 'optionSource' => 'groups', 'required' => true, 'description' => 'Group', 'displayOrder' => 9},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'switch' => 'default-cloud', 'fieldName' => 'defaultCloud', 'fieldLabel' => 'Default Cloud', 'type' => 'select', 'optionSource' => 'clouds', 'required' => false, 'description' => 'Default Cloud', 'displayOrder' => 10},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'switch' => 'environment', 'fieldName' => 'environment', 'fieldLabel' => 'Environment', 'type' => 'select', 'optionSource' => 'environments', 'required' => false, 'description' => 'Environment', 'displayOrder' => 11},
      {'dependsOnCode' => 'integrationObject.type:blueprint', 'switch' => 'config', 'fieldName' => 'config', 'fieldLabel' => 'Config', 'type' => 'code-editor', 'required' => true, 'description' => 'Config JSON', 'displayOrder' => 12},
      {'dependsOnCode' => 'integrationObject.type:catalog', 'switch' => 'catalog', 'fieldName' => 'catalog', 'fieldLabel' => 'Catalog Item', 'type' => 'select', 'optionSource' => 'catalogItemTypes', 'required' => true, 'description' => 'Catalog Item', 'displayOrder' => 13},
    ]
  end

  def add_integration_object_advanced_option_types
    []
  end

  def update_integration_object_option_types
    list = add_integration_object_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def update_integration_object_advanced_option_types
    add_integration_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
  end

  def integration_object_object_key
    'object'
  end

  def integration_object_list_key
    'objects'
  end

  def find_integration_object_by_name_or_id(integration_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_integration_object_by_id(integration_id, val)
    else
      return find_integration_object_by_name(integration_id, val)
    end
  end

  def find_integration_object_by_id(integration_id, id)
    begin
      json_response = @integrations_interface.get_object(integration_id, id.to_i)
      return json_response[integration_object_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "integration object not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_integration_object_by_name(integration_id, name)
    json_response = @integrations_interface.list_objects(integration_id, {name: name.to_s})
    integration_objects = json_response[integration_object_list_key]
    if integration_objects.empty?
      print_red_alert "integration object not found by name '#{name}'"
      return nil
    elsif integration_objects.size > 1
      print_red_alert "#{integration_objects.size} integration object found by name '#{name}'"
      puts_error as_pretty_table(integration_objects, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return integration_objects[0]
    end
  end

end
