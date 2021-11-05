require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkScopesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-scopes'
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
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network scopes." + "\n" +
        "[server] is required. This is the name or id of a network server."
    end

    optparse.parse!(args)
    connect(options)

    if args.count < 1
      puts optparse
      return 1
    end

    server = find_network_server(args[0])
    if server.nil?
      return 1
    end

    _list(server, options)
  end

  def _list(server, options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.list_scopes(server['id'])
      return
    end

    if server['type']['hasScopes']
      json_response = @network_servers_interface.list_scopes(server['id'])
      render_response(json_response, options, 'networkScopes') do
        print_h1 "Network Scopes For: #{server['name']}"
        print cyan
        print_scopes(server, json_response['networkScopes'])
      end
    else
      print_red_alert "Scopes not supported for #{server['type']['name']}"
    end
    print reset
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [scope]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network scope." + "\n" +
        "[server] is required. This is the name or id of a network server.\n" +
        "[scope] is required. This is the id of a network scope.\n"
    end

    optparse.parse!(args)
    connect(options)

    if args.count < 2
      puts optparse
      return 1
    end

    server = find_network_server(args[0])
    if server.nil?
      return 1
    end

    _get(server, args[1], options)
  end

  def _get(server, scope_id, options)
    @network_servers_interface.setopts(options)

    if options[:dry_run]
      if scope_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_servers_interface.dry.get_scope(server['id'], scope_id.to_i)
      else
        print_dry_run @network_servers_interface.dry.list_scopes(server['id'], {name: scope_id})
      end
      return
    end

    if server['type']['hasScopes']
      scope = find_scope(server['id'], scope_id)

      return 1 if scope.nil?

      render_response({networkScope: scope}, options, 'networkScope') do
        print_h1 "Network Scope Details"
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

        server['type']['scopeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, scope)
      end
    else
      print_red_alert "Scopes not supported for #{server['type']['name']}"
    end
    println reset
  end

  def add(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server]")
      opts.on( '--name NAME', "Name" ) do |val|
        options[:name] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        options[:description] = val.to_s
      end
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network scope." + "\n" +
        "[server] is required. This is the name or id of a network server.\n";
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end

    server = find_network_server(args[0])
    if server.nil?
      return 1
    end

    if !server['type']['hasScopes']
      print_red_alert "Scopes not supported for #{server['type']['name']}"
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
      print_green_success "\nAdded Network Scope #{json_response['id']}\n"
      _get(server, json_response['id'], options)
    end
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [scope]")
      opts.on( '--name NAME', "Name" ) do |val|
        params['name'] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        params['description'] = val.to_s
      end
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network scope.\n" +
        "[server] is required. This is the name or id of an existing network server.\n" +
        "[scope] is required. This is the name or id of an existing network scope."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server = find_network_server(args[0])
    if server.nil?
      return 1
    end

    if !server['type']['hasScopes']
      print_red_alert "Scopes not supported for #{server['type']['name']}"
      return 1
    end

    scope = find_scope(server['id'], args[1])
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
      print Morpheus::Cli::OptionTypes.display_option_types_help(
        option_types,
        {:include_context => true, :context_map => {'scope' => ''}, :color => cyan, :title => "Available Scope Options"}
      )
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
      print_green_success "\nUpdated Network Scope #{scope['id']}\n"
      _get(server, scope['id'], options)
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [scope]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network scope.\n" +
        "[server] is required. This is the name or id of an existing network server.\n" +
        "[scope] is required. This is the name or id of an existing network scope."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)

    server = find_network_server(args[0])
    if server.nil?
      return 1
    end

    if !server['type']['hasScopes']
      print_red_alert "Scopes not supported for #{server['type']['name']}"
      return 1
    end

    scope = find_scope(server['id'], args[1])
    return 1 if scope.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network scope '#{scope['name']}' from server '#{server['name']}'?", options)
      return 9, "aborted command"
    end

    @network_servers_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.destroy_scope(server['id'], scope['id'])
      return
    end
    json_response = @network_servers_interface.destroy_scope(server['id'], scope['id'])
    render_response(json_response, options, 'networkScope') do
      print_green_success "\nDeleted Network Scope #{scope['name']}\n"
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
      println "No Scopes\n"
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
    json_response = @network_servers_interface.list({phrase: name.to_s})
    servers = json_response['networkServers']
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
        print_red_alert "Network Scope not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_scope_by_name(server_id, name)
    json_response = @network_servers_interface.list_scope(server_id, {phrase: name.to_s})
    scopes = json_response['networkScopes']
    if scopes.empty?
      print_red_alert "Network Scope not found by name #{name}"
      return nil
    elsif scopes.size > 1
      print_red_alert "#{scopes.size} network scopes found by name #{name}"
      rows = scopes.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return scopes[0]
    end
  end

end
