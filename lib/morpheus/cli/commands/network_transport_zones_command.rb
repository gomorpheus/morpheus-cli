require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkTransportZonesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-transport-zones'
  register_subcommands :list, :get, :add, :update, :remove

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_interface = @api_client.accounts
    @network_servers_interface = @api_client.network_servers
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server]")
      build_common_options(opts, options, [:list, :query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network transport zones." + "\n" +
        "[server] is optional. This is the name or id of a network server."
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    _list(server, options)
  end

  def _list(server, options)
    params = parse_list_options(options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.list_scopes(server['id'], params)
      return
    end

    if server['type']['hasScopes']
      json_response = @network_servers_interface.list_scopes(server['id'], params)
      render_response(json_response, options, 'networkScopes') do
        print_h1 "Network transport zones For: #{server['name']}"
        print cyan
        print_scopes(server, json_response['networkScopes'])
      end
    else
      print_red_alert "Transport zones not supported for #{server['type']['name']}"
    end
    print reset
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [transport zone]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network transport zone." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n" +
        "[transport zone] is optional. This is the id of a network transport zone.\n"
    end

    optparse.parse!(args)
    connect(options)

    if args.count > 2
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    scope_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'rule', 'type' => 'select', 'fieldLabel' => 'Transport Zone', 'selectOptions' => search_scopes(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Transport Zone.'}],options[:options],@api_client,{})['rule']

    _get(server, scope_id, options)
  end

  def _get(server, scope_id, options)
    params = parse_list_options(options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      if scope_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_servers_interface.dry.get_scope(server['id'], scope_id.to_i, params)
      else
        print_dry_run @network_servers_interface.dry.list_scopes(server['id'], {name: scope_id}, params)
      end
      return
    end

    if server['type']['hasScopes']
      scope = find_scope(server['id'], scope_id)

      return 1 if scope.nil?

      render_response({networkScope: scope}, options, 'networkScope') do
        print_h1 "Network Transport Zone Details"
        print cyan

        description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']},
          "Description" => lambda {|it| it['description']},
          "Status" => lambda {|it| it['status']}
        }

        if is_master_account
          description_cols["Visibility"] = lambda {|it| it['visibility']}
          description_cols["Tenants"] = lambda {|it| it['tenants'].collect {|tenant| tenant['name']}.join(', ')}
        end

        server['type']['scopeOptionTypes'].reject {|it| it['type'] == 'hidden'}.sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, scope)
      end
    else
      print_red_alert "Transport zones not supported for #{server['type']['name']}"
    end
    println reset
  end

  def add(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server]")
      opts.on('-n', '--name VALUE', String, "Name" ) do |val|
        options[:options]['name'] = val.to_s
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        options[:options]['description'] = val.to_s
      end
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network transport zone." + "\n" +
        "[server] is optional. This is the name or id of a network server.\n";
    end
    optparse.parse!(args)
    connect(options)

    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasScopes']
      print_red_alert "Transport zones not supported for #{server['type']['name']}"
      return 1
    end

    if options[:payload]
      payload = options[:payload]
    else
      params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'type' => 'text', 'fieldLabel' => 'Name', 'required' => true, 'description' => 'Name.'}],options[:options],@api_client,{})['name']
      params['description'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'type' => 'text', 'fieldLabel' => 'Description', 'required' => false, 'description' => 'Description.'}],options[:options],@api_client,{})['description']

      option_types = server['type']['scopeOptionTypes'].sort_by {|it| it['displayOrder']}

      # prompt options
      option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'scope' => ''}}), @api_client, {'networkServerId' => server['id']}, nil, true)

      # prompt permissions
      perms = prompt_permissions(options, ['plans', 'groups'])
      perms = {'visibility' => perms['resourcePool']['visibility'], 'tenants' => perms['tenantPermissions']['accounts'].collect {|it| {'id' => it}}}
      payload = {'networkScope' => params.deep_merge(option_result).deep_merge(perms)}
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.create_scope(server['id'], payload)
      return
    end

    json_response = @network_servers_interface.create_scope(server['id'], payload)
    render_response(json_response, options, 'networkScope') do
      print_green_success "\nAdded Network Transport Zone #{json_response['id']}\n"
      _get(server, json_response['id'], options)
    end
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [transport zone]")
      opts.on('-n', '--name VALUE', String, "Name" ) do |val|
        options[:options]['name'] = val.to_s
      end
      opts.on('-D', '--description VALUE', String, "Description") do |val|
        options[:options]['description'] = val.to_s
      end
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network transport zone.\n" +
        "[server] is optional. This is the name or id of an existing network server.\n" +
        "[transport zone] is optional. This is the name or id of an existing network transport zone."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasScopes']
      print_red_alert "Transport zones not supported for #{server['type']['name']}"
      return 1
    end

    scope_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scope', 'type' => 'select', 'fieldLabel' => 'Transport Zone', 'selectOptions' => search_scopes(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Transport Zone.'}],options[:options],@api_client,{})['scope']
    scope = find_scope(server['id'], scope_id)
    return 1 if scope.nil?

    payload = parse_payload(options) || {'networkScope' => params}
    payload['networkScope'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['networkScope'].nil?

    if !options[:visibility].nil?
      payload['networkScope']['visibility'] = options[:visibility]
    end
    if !options[:tenants].nil?
      payload['networkScope']['tenants'] = options[:tenants].collect {|id| {id: id.to_i}}
    end

    if payload['networkScope'].empty?
      option_types = server['type']['scopeOptionTypes'].sort_by {|it| it['displayOrder']}
      print_green_success "Nothing to update"
      println cyan
      edit_option_types = option_types.reject {|it| !it['editable'] || !it['showOnEdit']}

      if edit_option_types.count > 0
        print Morpheus::Cli::OptionTypes.display_option_types_help(
          option_types,
          {:include_context => true, :context_map => {'scope' => ''}, :color => cyan, :title => "Available Transport Zone Options"}
        )
      end
      exit 1
    end

    #payload = {'networkScope' => scope.deep_merge(payload['networkScope'])}

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.update_scope(server['id'], scope['id'], payload)
      return
    end

    json_response = @network_servers_interface.update_scope(server['id'], scope['id'], payload)
    render_response(json_response, options, 'networkScope') do
      print_green_success "\nUpdated Network Transport Zone #{scope['id']}\n"
      _get(server, scope['id'], options)
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [transport zone]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network transport zone.\n" +
        "[server] is optional. This is the name or id of an existing network server.\n" +
        "[transport zone] is optional. This is the name or id of an existing network transport zone."
    end
    optparse.parse!(args)
    if args.count > 2
      raise_command_error "wrong number of arguments, expected 0-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server_id = args.count > 0 ? args[0] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'networkServer', 'type' => 'select', 'fieldLabel' => 'Network Server', 'selectOptions' => search_network_servers.collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Network Server.'}],options[:options],@api_client,{})['networkServer']
    server = find_network_server(server_id)
    return 1 if server.nil?

    if !server['type']['hasScopes']
      print_red_alert "Transport zones not supported for #{server['type']['name']}"
      return 1
    end

    scope_id = args.count > 1 ? args[1] : Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'scope', 'type' => 'select', 'fieldLabel' => 'Transport Zone', 'selectOptions' => search_scopes(server['id']).collect {|it| {'name' => it['name'], 'value' => it['id']}}, 'required' => true, 'description' => 'Select Transport Zone.'}],options[:options],@api_client,{})['scope']
    scope = find_scope(server['id'], scope_id)
    return 1 if scope.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network transport zone '#{scope['name']}' from server '#{server['name']}'?", options)
      return 9, "aborted command"
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.destroy_scope(server['id'], scope['id'])
      return
    end
    json_response = @network_servers_interface.destroy_scope(server['id'], scope['id'])
    render_response(json_response, options, 'networkScope') do
      print_green_success "\nDeleted Network Transport Zone #{scope['name']}\n"
      _list(server, options)
    end
  end

  private

  def print_scopes(server, scopes)
    if scopes.count > 0
      cols = [:id, :name, :description, :status]
      server['type']['scopeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
        cols << option_type['fieldLabel']
      end
      cols += [:visibility, :tenants] if is_master_account
      rows = scopes.collect do |it|
        row = {
          id: it['id'],
          name: it['name'],
          description: it['description'],
          status: it['statusMessage'],
        }
        server['type']['scopeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          row[option_type['fieldLabel']] = Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)
        end
        if is_master_account
          row = row.merge({
            visibility: it['visibility'],
            tenants: it['tenants'].collect {|it| it['name']}.join(', ')
          })
        end
        row
      end
      puts as_pretty_table(rows, cols)
    else
      println "No transport zones\n"
    end
  end

  def find_network_server(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_server_by_id(val)
    else
      if server = find_network_server_by_name(val)
        return find_network_server_by_id(server['id'])
      end
    end
  end

  def find_network_server_by_id(id)
    begin
      json_response = @network_servers_interface.get(id.to_i)
      return json_response['networkServer']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Server not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_server_by_name(name)
    servers = search_network_servers(name)
    if servers.empty?
      print_red_alert "Network Server not found by name #{name}"
      return nil
    elsif servers.size > 1
      print_red_alert "#{servers.size} network servers found by name #{name}"
      rows = servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return servers[0]
    end
  end

  def search_network_servers(phrase = nil)
    @network_servers_interface.list(phrase ? {phrase: phrase.to_s} : {})['networkServers']
  end

  def find_scope(server_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_scope_by_id(server_id, val)
    else
      if scope = find_scope_by_name(server_id, val)
        return find_scope_by_id(server_id, scope['id'])
      end
    end
  end

  def find_scope_by_id(server_id, scope_id)
    begin
      json_response = @network_servers_interface.get_scope(server_id, scope_id.to_i)
      return json_response['networkScope']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network transport zone not found by id #{scope_id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_scope_by_name(server_id, name)
    scopes = search_scopes(server_id, name)
    if scopes.empty?
      print_red_alert "Network transport zone not found by name #{name}"
      return nil
    elsif scopes.size > 1
      print_red_alert "#{scopes.size} network transport zones found by name #{name}"
      rows = scopes.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return scopes[0]
    end
  end

  def search_scopes(server_id, phrase = nil)
    @network_servers_interface.list_scopes(server_id, phrase ? {phrase: phrase.to_s} : {})['networkScopes']
  end

end
