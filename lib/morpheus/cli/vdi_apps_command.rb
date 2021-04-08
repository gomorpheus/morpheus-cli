require 'morpheus/cli/cli_command'

# CLI command VDI App management
# UI is Tools: VDI Apps
# API is /vdi-apps and returns vdiApps
class Morpheus::Cli::VdiAppsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::VdiHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'vdi-apps'
  set_command_description "View and manage VDI apps"

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @vdi_apps_interface = @api_client.vdi_apps
    @vdi_apps_interface = @api_client.vdi_apps
    @vdi_apps_interface = @api_client.vdi_apps
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
      opts.footer = "List VDI apps."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @vdi_apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_apps_interface.dry.list(params)
      return
    end
    json_response = @vdi_apps_interface.list(params)
    render_response(json_response, options, vdi_app_list_key) do
      vdi_apps = json_response[vdi_app_list_key]
      print_h1 "Morpheus VDI Apps", parse_list_subtitles(options), options
      if vdi_apps.empty?
        print cyan,"No VDI apps found.",reset,"\n"
      else
        print as_pretty_table(vdi_apps, vdi_app_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[app]")
      opts.on( '-c', '--config', "Display raw config only. Default is YAML. Combine with -j for JSON instead." ) do
        options[:show_config] = true
      end
      # opts.on('--no-config', "Do not display Config YAML." ) do
      #   options[:no_config] = true
      # end
      opts.on('--no-content', "Do not display Content." ) do
        options[:no_content] = true
      end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific VDI app.
[app] is required. This is the name or id of a VDI app.
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
    vdi_app = nil
    if id.to_s !~ /\A\d{1,}\Z/
      vdi_app = find_vdi_app_by_name(id)
      return 1, "VDI app not found for #{id}" if vdi_app.nil?
      id = vdi_app['id']
    end
    @vdi_apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_apps_interface.dry.get(id, params)
      return
    end
    json_response = @vdi_apps_interface.get(id, params)
    vdi_app = json_response[vdi_app_object_key]
    config = vdi_app['config'] || {}
    # export just the config as json or yaml (default)
    if options[:show_config]
      unless options[:json] || options[:yaml] || options[:csv]
        options[:yaml] = true
      end
      return render_with_format(config, options)
    end
    render_response(json_response, options, vdi_app_object_key) do
      print_h1 "VDI App Details", [], options
      print cyan
      show_columns = vdi_app_column_definitions
      show_columns.delete("VDI Apps") unless vdi_app['apps']
      show_columns.delete("VDI App") unless vdi_app['app']
      show_columns.delete("Guest Console Jump Host") unless vdi_app['guestConsoleJumpHost']
      show_columns.delete("Guest Console Jump Port") unless vdi_app['guestConsoleJumpPort']
      show_columns.delete("Guest Console Jump Username") unless vdi_app['guestConsoleJumpUsername']
      show_columns.delete("Guest Console Jump Password") unless vdi_app['guestConsoleJumpPassword']
      show_columns.delete("Guest Console Jump Keypair") unless vdi_app['guestConsoleJumpKeypair']
      print_description_list(show_columns, vdi_app)


      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_vdi_app_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new VDI app.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_app_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({vdi_app_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_vdi_app_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      params.booleanize!
      payload[vdi_app_object_key].deep_merge!(params)
    end
    @vdi_apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_apps_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @vdi_apps_interface.create(payload)
    vdi_app = json_response[vdi_app_object_key]
    render_response(json_response, options, vdi_app_object_key) do
      print_green_success "Added VDI app #{vdi_app['name']}"
      return _get(vdi_app["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_option_type_options(opts, options, update_vdi_app_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a VDI app.
[app] is required. This is the name or id of a VDI app.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    vdi_app = find_vdi_app_by_name_or_id(args[0])
    return 1 if vdi_app.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_app_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({vdi_app_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_vdi_app_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      params.booleanize!
      payload.deep_merge!({vdi_app_object_key => params})
      if payload[vdi_app_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @vdi_apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_apps_interface.dry.update(vdi_app['id'], payload)
      return
    end
    json_response = @vdi_apps_interface.update(vdi_app['id'], payload)
    vdi_app = json_response[vdi_app_object_key]
    render_response(json_response, options, vdi_app_object_key) do
      print_green_success "Updated VDI app #{vdi_app['name']}"
      return _get(vdi_app["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[app] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a VDI app.
[app] is required. This is the name or id of a VDI app.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    vdi_app = find_vdi_app_by_name_or_id(args[0])
    return 1 if vdi_app.nil?
    @vdi_apps_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_apps_interface.dry.destroy(vdi_app['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the VDI app #{vdi_app['name']}?")
      return 9, "aborted command"
    end
    json_response = @vdi_apps_interface.destroy(vdi_app['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed VDI app #{vdi_app['name']}"
    end
    return 0, nil
  end

  private
  
  def vdi_app_list_column_definitions()

    {
      "ID" => 'id',
      "Name" => 'name',
      # "Description" => 'description',
      "Launch Prefix" => 'launchPrefix',
      # "Logo" => 'logo',
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def vdi_app_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Launch Prefix" => 'launchPrefix',
      "Logo" => 'logo',
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_vdi_app_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Choose a unique name for the VDI App'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description'},
      {'fieldName' => 'launchPrefix', 'fieldLabel' => 'Launch Prefix', 'type' => 'text', 'required' => true, 'description' => 'The RDS App Name Prefix. Note: Must start with || (i.e. ||notepad) to launch notepad'},
      {'fieldName' => 'iconPath', 'fieldLabel' => 'Logo', 'type' => 'select', 'optionSource' => 'iconList', 'defaultValue' => 'resource'},
    ]
  end

  def update_vdi_app_option_types
    list = add_vdi_app_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  # finders are in VdiHelper mixin

end
