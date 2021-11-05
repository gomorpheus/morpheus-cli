require 'morpheus/cli/cli_command'

# CLI command VDI Gateway management
# UI is Tools: VDI Gateways
# API is /vdi-gateways and returns vdiGateways
class Morpheus::Cli::VdiGatewaysCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::VdiHelper
  include Morpheus::Cli::OptionSourceHelper

  set_command_name :'vdi-gateways'
  set_command_description "View and manage VDI gateways"

  register_subcommands :list, :get, :add, :update, :remove
  
  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @vdi_gateways_interface = @api_client.vdi_gateways
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
      build_standard_list_options(opts, options)
      opts.footer = "List VDI gateways."
    end
    optparse.parse!(args)
    connect(options)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @vdi_gateways_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_gateways_interface.dry.list(params)
      return
    end
    json_response = @vdi_gateways_interface.list(params)
    render_response(json_response, options, vdi_gateway_list_key) do
      vdi_gateways = json_response[vdi_gateway_list_key]
      print_h1 "Morpheus VDI Gateways", parse_list_subtitles(options), options
      if vdi_gateways.empty?
        print cyan,"No VDI gateways found.",reset,"\n"
      else
        print as_pretty_table(vdi_gateways, vdi_gateway_list_column_definitions.upcase_keys!, options)
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
      opts.banner = subcommand_usage("[gateway]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific VDI gateway.
[gateway] is required. This is the name or id of a VDI gateway.
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
    vdi_gateway = nil
    if id.to_s !~ /\A\d{1,}\Z/
      vdi_gateway = find_vdi_gateway_by_name(id)
      return 1, "VDI gateway not found for #{id}" if vdi_gateway.nil?
      id = vdi_gateway['id']
    end
    @vdi_gateways_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_gateways_interface.dry.get(id, params)
      return
    end
    json_response = @vdi_gateways_interface.get(id, params)
    vdi_gateway = json_response[vdi_gateway_object_key]
    config = vdi_gateway['config'] || {}
    # export just the config as json or yaml (default)
    if options[:show_config]
      unless options[:json] || options[:yaml] || options[:csv]
        options[:yaml] = true
      end
      return render_with_format(config, options)
    end
    render_response(json_response, options, vdi_gateway_object_key) do
      print_h1 "VDI Gateway Details", [], options
      print cyan
      show_columns = vdi_gateway_column_definitions
      show_columns.delete("VDI Apps") unless vdi_gateway['apps']
      show_columns.delete("VDI Gateway") unless vdi_gateway['gateway']
      show_columns.delete("Guest Console Jump Host") unless vdi_gateway['guestConsoleJumpHost']
      show_columns.delete("Guest Console Jump Port") unless vdi_gateway['guestConsoleJumpPort']
      show_columns.delete("Guest Console Jump Username") unless vdi_gateway['guestConsoleJumpUsername']
      show_columns.delete("Guest Console Jump Password") unless vdi_gateway['guestConsoleJumpPassword']
      show_columns.delete("Guest Console Jump Keypair") unless vdi_gateway['guestConsoleJumpKeypair']
      print_description_list(show_columns, vdi_gateway)


      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_option_type_options(opts, options, add_vdi_gateway_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new VDI gateway.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    options[:options]['name'] = args[0] if args[0]
    connect(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_gateway_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({vdi_gateway_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_vdi_gateway_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      params.booleanize!
      payload[vdi_gateway_object_key].deep_merge!(params)
    end
    @vdi_gateways_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_gateways_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @vdi_gateways_interface.create(payload)
    vdi_gateway = json_response[vdi_gateway_object_key]
    render_response(json_response, options, vdi_gateway_object_key) do
      print_green_success "Added VDI gateway #{vdi_gateway['name']}"
      return _get(vdi_gateway["id"], {}, options)
    end
    return 0, nil
  end

  def update(args)
    options = {}
    params = {}
    payload = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[gateway] [options]")
      build_option_type_options(opts, options, update_vdi_gateway_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a VDI gateway.
[gateway] is required. This is the name or id of a VDI gateway.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    vdi_gateway = find_vdi_gateway_by_name_or_id(args[0])
    return 1 if vdi_gateway.nil?
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({vdi_gateway_object_key => parse_passed_options(options)})
    else
      payload.deep_merge!({vdi_gateway_object_key => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(update_vdi_gateway_option_types, options[:options], @api_client, options[:params])
      v_prompt.deep_compact!
      params.deep_merge!(v_prompt)
      params.booleanize!
      payload.deep_merge!({vdi_gateway_object_key => params})
      if payload[vdi_gateway_object_key].empty? # || options[:no_prompt]
        raise_command_error "Specify at least one option to update.\n#{optparse}"
      end
    end
    @vdi_gateways_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_gateways_interface.dry.update(vdi_gateway['id'], payload)
      return
    end
    json_response = @vdi_gateways_interface.update(vdi_gateway['id'], payload)
    vdi_gateway = json_response[vdi_gateway_object_key]
    render_response(json_response, options, vdi_gateway_object_key) do
      print_green_success "Updated VDI gateway #{vdi_gateway['name']}"
      return _get(vdi_gateway["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[gateway] [options]")
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a VDI gateway.
[gateway] is required. This is the name or id of a VDI gateway.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    vdi_gateway = find_vdi_gateway_by_name_or_id(args[0])
    return 1 if vdi_gateway.nil?
    @vdi_gateways_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @vdi_gateways_interface.dry.destroy(vdi_gateway['id'], params)
      return
    end
    unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the VDI gateway #{vdi_gateway['name']}?")
      return 9, "aborted command"
    end
    json_response = @vdi_gateways_interface.destroy(vdi_gateway['id'], params)
    render_response(json_response, options) do
      print_green_success "Removed VDI gateway #{vdi_gateway['name']}"
    end
    return 0, nil
  end

  private
  
  def vdi_gateway_list_column_definitions()

    {
      "ID" => 'id',
      "Name" => 'name',
      # "Description" => 'description',
      "Gateway URL" => 'gatewayUrl',
      "API Key" => 'apiKey',
      # "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      # "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def vdi_gateway_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Gateway URL" => 'gatewayUrl',
      "API Key" => 'apiKey',
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def add_vdi_gateway_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Choose a unique name for the VDI Gateway'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'description' => 'Description'},
      {'fieldName' => 'gatewayUrl', 'fieldLabel' => 'Gateway URL', 'type' => 'text', 'required' => true, 'description' => 'URL of the VDI Gateway'},
    ]
  end

  def update_vdi_gateway_option_types
    list = add_vdi_gateway_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  # finders are in VdiHelper mixin

end
