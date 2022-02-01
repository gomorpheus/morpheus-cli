require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkStaticRoutesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-static-routes'
  register_subcommands :list, :get, :add, :remove, :update

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_interface = @api_client.accounts
    @network_static_routes_interface = @api_client.network_static_routes
    @networks_interface = @api_client.networks
    @network_types_interface = @api_client.network_types  
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network] [search]")
      build_standard_list_options(opts, options)
      opts.footer = "List network DHCP Static Routes." + "\n" +
        "[network] is required. This is the name or id of a network."
    end

    optparse.parse!(args)
    connect(options)

    verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 1
      options[:phrase] = args[1..-1].join(" ")
    end
    
    network = find_network(args[0])
    if network.nil?
      return 1
    end
    
    network_type = find_network_type(network['type']['id'])
    if network_type.nil?
      return 1
    end

    _list(network, network_type, options)
  end

  def _list(network, network_type, options)
    params = parse_list_options(options)
    @network_static_routes_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @network_static_routes_interface.dry.list_static_routes(network['id'], params)
      return
    end

    json_response = @network_static_routes_interface.list_static_routes(network['id'], params)
    render_response(json_response, options, 'networkRoutes') do
      print_h1 "Network DHCP Static Routes For: #{network['name']}"
      print_static_routes(network, network_type, json_response)
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network] [network_route]")
      build_standard_get_options(opts, options)
      opts.footer = "Display details on a network Static Route." + "\n" +
        "[network] is required. This is the name or id of a network.\n" +
        "[network_route] is required. This is the id of a network route.\n"
    end

    optparse.parse!(args)
    connect(options)

    verify_args!(args:args, optparse:optparse, count:2)

    network = find_network(args[0])
    if network.nil?
      return 1
    end
    
    network_type = find_network_type(network['type']['id'])
    if network_type.nil?
      return 1
    end

    _get(network, network_type, args[1], options)
  end

  def _get(network, network_type, route_id, options)
    # params = parse_query_options(options) # todo: use this
    @network_static_routes_interface.setopts(options)

    if options[:dry_run]
      if route_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_static_routes_interface.dry.get_static_route(network['id'], route_id.to_i)
      else
        print_dry_run @network_static_routes_interface.dry.list_static_routes(network['id'], {name: route_id})
      end
      return
    end

    route = find_static_route(network['id'], route_id)
    return 1 if route.nil?

    render_response({route: route}, options, 'route') do
      print_h1 "Network Route Details"
      print cyan

      description_cols = {}

      network_type['routeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
        description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
      end
      print_description_list(description_cols, route)
    end

    println reset
  end

  def add(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[network]")
      build_standard_add_options(opts, options)
      opts.footer = "Create a network static route." + "\n" +
        "[network] is required. This is the name or id of a network.\n";
    end
    optparse.parse!(args)
    connect(options)
    verify_args!(args:args, optparse:optparse, count:1)

    network = find_network(args[0])
    if network.nil?
      return 1
    end
    
    network_type = find_network_type(network['type']['id'])
    if network_type.nil?
      return 1
    end

    if !network_type['hasStaticRoutes']
      print_red_alert "Static routes not supported for #{network_type['name']}"
      return 1
    end

    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      option_types = network_type['routeOptionTypes'].sort_by {|it| it['displayOrder']}
      # prompt options
      option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'networkRoute' => ''}}), @api_client, {'networkId' => network['id']}, nil, true)
      payload = {'networkRoute' => params.deep_merge(option_result)}
      # copy all domain level fields to route
      if payload['networkRoute']['domain']
        payload['networkRoute']['domain'].each do |k,v|
          payload['networkRoute'][k] = v
        end
      end
      payload['networkRoute'].delete('domain')

    end

    @network_static_routes_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_static_routes_interface.dry.create_static_route(network['id'], payload)
      return
    end

    json_response = @network_static_routes_interface.create_static_route(network['id'], payload)
    render_response(json_response, options, 'networkRoute') do
      print_green_success "\nAdded Network Static Route #{json_response['id']}\n"
      _get(network, network_type, json_response['id'], options)
    end
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[network] [networkRoute]")
      build_standard_update_options(opts, options)
      opts.footer = "Update a network Static Route.\n" +
        "[network] is required. This is the name or id of an existing network.\n" +
        "[networkRoute] is required. This is the name or id of an existing network static route."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)

    network = find_network(args[0])
    if network.nil?
      return 1
    end
    
    network_type = find_network_type(network['type']['id'])
    if network_type.nil?
      return 1
    end

    route = find_static_route(network['id'], args[1])
    return 1 if route.nil?

    payload = parse_payload(options) || {'networkRoute' => params}
    payload['networkRoute'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['networkRoute'].nil?

    if payload['networkRoute'].empty?
      option_types = network_type['routeOptionTypes'].sort_by {|it| it['displayOrder']}
      print_green_success "Nothing to update"
      println cyan
      print Morpheus::Cli::OptionTypes.display_option_types_help(
        option_types,
        {:include_context => true, :context_map => {'networkRoute' => ''}, :color => cyan, :title => "Available Network Static Route Options"}
      )
      exit 1
    end

	# copy all domain level fields to route
	if payload['networkRoute']['domain']
      payload['networkRoute']['domain'].each do |k,v|
        payload['networkRoute'][k] = v
      end
      payload['networkRoute'].delete('domain')
    end

    @network_static_routes_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_static_routes_interface.dry.update_static_route(network['id'], route['id'], payload)
      return
    end
    
    # build update payload
    update_payload = {'networkRoute' => route.select{|x| !['id', 'code', 'internalId', 'externalId', 'uniqueId', 'providerId', 'externalType', 'enabled', 'visible', 'externalInterface'].include?(x)}}.deep_merge(payload)

    json_response = @network_static_routes_interface.update_static_route(network['id'], route['id'], update_payload)
    render_response(json_response, options, 'networkRoute') do
      print_green_success "\nUpdated Network Static Route #{route['id']}\n"
      _get(network, network_type, route['id'], options)
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network] [network_route]")
      build_standard_remove_options(opts, options)
      opts.footer = "Delete a network static route.\n" +
        "[network] is required. This is the name or id of an existing network.\n" +
        "[network_route] is required. This is the name or id of an existing network static route."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:2)
    connect(options)

    network = find_network(args[0])
    if network.nil?
      return 1
    end
    
    network_type = find_network_type(network['type']['id'])
    if network_type.nil?
      return 1
    end

    route = find_static_route(network['id'], args[1])
    return 1 if route.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network static route '#{route['source']},#{route['destination']}' from network '#{network['name']}'?", options)
      return 9, "aborted command"
    end

    @network_static_routes_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_static_routes_interface.dry.delete_static_routes(network['id'], route['id'])
      return
    end
    json_response = @network_static_routes_interface.delete_static_route(network['id'], route['id'])
    render_response(json_response, options, 'networkRoute') do
      print_green_success "\nDeleted Network Static Route '#{route['source']},#{route['destination']}'\n"
      _list(network, network_type, options)
    end
  end

  private

  def print_static_routes(network, network_type, json_response)
    routes = json_response['networkRoutes']
    print cyan
    if routes.count > 0
      cols = [:id]
      network_type['routeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
        cols << option_type['fieldLabel']
      end
      rows = routes.collect do |it|
        row = {
          id: it['id']
        }
        network_type['routeOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          row[option_type['fieldLabel']] = Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)
        end
        row
      end
      print as_pretty_table(rows, cols)
      print_results_pagination(json_response)
    else
      println "No Static Routes"
    end
    println reset
  end

  def find_network(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_by_id(val)
    else
      if network = find_network_by_name(val)
        return find_network_by_id(network['id'])
      end
    end
  end

  def find_network_by_id(id)
    begin
      json_response = @networks_interface.get(id.to_i)
      return json_response['network']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_by_name(name)
    json_response = @networks_interface.list({phrase: name.to_s})
    networks = json_response['network']
    if networks.empty?
      print_red_alert "Network not found by name #{name}"
      return nil
    elsif networks.size > 1
      print_red_alert "#{networks.size} network found by name #{name}"
      rows = networks.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return networks[0]
    end
  end
  
  def find_network_type(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_type_by_id(val)
    else
      if network_type = find_network_type_by_name(val)
        return find_network_type_by_id(network_type['id'])
      end
    end
  end

  def find_network_type_by_id(id)
    begin
      json_response = @network_types_interface.get(id.to_i)
      return json_response['networkType']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_type_by_name(name)
    json_response = @network_types_interface.list({phrase: name.to_s})
    networkTypes = json_response['networkType']
    if networkTypes.empty?
      print_red_alert "Network Type not found by name #{name}"
      return nil
    elsif networkTypes.size > 1
      print_red_alert "#{networkTypes.size} network type found by name #{name}"
      rows = networkTypes.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return networkTypes[0]
    end
  end

  def find_static_route(network_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_static_route_by_id(network_id, val)
    else
      if route = find_static_route_by_name(network_id, val)
        return find_static_route_by_id(network_id, route['id'])
      end
    end
  end

  def find_static_route_by_id(network_id, route_id)
    begin
      json_response = @network_static_routes_interface.get_static_route(network_id, route_id.to_i)
      return json_response['networkRoute']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Static Route not found by id #{route_id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_static_route_by_name(network_id, name)
    json_response = @network_static_routes_interface.list_static_routes(network_id, {phrase: name.to_s})
    routes = json_response['networkRoutes']
    if routes.empty?
      print_red_alert "Network Static Routes not found by name #{name}"
      return nil
    elsif routes.size > 1
      print_red_alert "#{routes.size} network Static Routes found by name #{name}"
      rows = routes.collect do |it|
        {id: it['id'], source: it['source'], destination: it['destination']}
      end
      puts as_pretty_table(rows, [:id, :source, :destination], {color:red})
      return nil
    else
      return routes[0]
    end
  end

end
