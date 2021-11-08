require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkDhcpRelaysCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-dhcp-relays'
  register_subcommands :list, :get, :add, :remove, :update

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_interface = @api_client.accounts
    @network_dhcp_relays_interface = @api_client.network_dhcp_relays
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
      opts.footer = "List network DHCP Relays." + "\n" +
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
    @network_dhcp_relays_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_dhcp_relays_interface.dry.list_dhcp_relays(server['id'])
      return
    end

    if server['type']['hasDhcpRelays']
      json_response = @network_dhcp_relays_interface.list_dhcp_relays(server['id'])
      render_response(json_response, options, 'networkDhcpRelays') do
        print_h1 "Network DHCP Relays For: #{server['name']}"
        print cyan
        print_dhcp_relays(server, json_response['networkDhcpRelays'])
      end
    else
      print_red_alert "DHCP Relays not supported for #{server['type']['name']}"
    end
    print reset
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [dhcp_relay]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network DHCP Relay." + "\n" +
        "[server] is required. This is the name or id of a network server.\n" +
        "[dhcp_relay] is required. This is the id of a network DHCP Relay.\n"
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

  def _get(server, dhcp_relay_id, options)
    @network_dhcp_relays_interface.setopts(options)

    if options[:dry_run]
      if dhcp_relay_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_dhcp_relays_interface.dry.get_dhcp_relay(server['id'], dhcp_relay_id.to_i)
      else
        print_dry_run @network_dhcp_relays_interface.dry.list_dhcp_relays(server['id'], {name: dhcp_relay_id})
      end
      return
    end

    if server['type']['hasDhcpRelays']
      dhcpRelay = find_dhcp_relay(server['id'], dhcp_relay_id)
      return 1 if dhcpRelay.nil?

      render_response({networkDhcpRelay: dhcpRelay}, options, 'networkDhcpRelay') do
        print_h1 "Network DHCP Relay Details"
        print cyan

        description_cols = {
          "ID" => lambda {|it| it['id']},
          "Name" => lambda {|it| it['name']}
        }

        server['type']['dhcpRelayOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, dhcpRelay)
      end
    else
      print_red_alert "DHCP Relays not supported for #{server['type']['name']}"
    end
    println reset
  end

  def add(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Create a network dhcp relay." + "\n" +
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

    if !server['type']['hasDhcpRelays']
      print_red_alert "DHCP Relays not supported for #{server['type']['name']}"
      return 1
    end

    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      option_types = server['type']['dhcpRelayOptionTypes'].sort_by {|it| it['displayOrder']}
      # prompt options
      option_result = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options].deep_merge({:context_map => {'networkDhcpRelay' => ''}}), @api_client, {'networkServerId' => server['id']}, nil, true)
      payload = {'networkDhcpRelay' => params.deep_merge(option_result)}
      # copy all domain level fields to networkDhcpRelay
      if payload['networkDhcpRelay']['domain']
        payload['networkDhcpRelay']['domain'].each do |k,v|
          payload['networkDhcpRelay'][k] = v
        end
      end
      payload['networkDhcpRelay'].delete('domain')

    end

    @network_dhcp_relays_interface.setopts(options)

    serverIpAddresses = payload['networkDhcpRelay']['serverIpAddresses']
	if !serverIpAddresses.nil?
	  if !serverIpAddresses.kind_of?(Array)
	    payload['networkDhcpRelay']['serverIpAddresses'] = serverIpAddresses.to_s.split(',')
	  end
    end

    if options[:dry_run]
      print_dry_run @network_dhcp_relays_interface.dry.create_dhcp_relay(server['id'], payload)
      return
    end

    json_response = @network_dhcp_relays_interface.create_dhcp_relay(server['id'], payload)
    render_response(json_response, options, 'networkDhcpRelay') do
      print_green_success "\nAdded Network DHCP Relay #{json_response['id']}\n"
      _get(server, json_response['id'], options)
    end
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [dhcp_relay]")
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network DHCP Relay.\n" +
        "[server] is required. This is the name or id of an existing network server.\n" +
        "[dhcp_relay] is required. This is the name or id of an existing network DHCP Relay."
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

    if !server['type']['hasDhcpRelays']
      print_red_alert "DHCP Relays not supported for #{server['type']['name']}"
      return 1
    end

    dhcpRelay = find_dhcp_relay(server['id'], args[1])
    return 1 if dhcpRelay.nil?

    payload = parse_payload(options) || {'networkDhcpRelay' => params}
    payload['networkDhcpRelay'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['networkDhcpRelay'].nil?

    if payload['networkDhcpRelay'].empty?
      option_types = server['type']['dhcpRelayOptionTypes'].sort_by {|it| it['displayOrder']}
      print_green_success "Nothing to update"
      println cyan
      print Morpheus::Cli::OptionTypes.display_option_types_help(
        option_types,
        {:include_context => true, :context_map => {'networkDhcpRelay' => ''}, :color => cyan, :title => "Available DHCP Relay Options"}
      )
      exit 1
    end

	# copy all domain level fields to networkDhcpRelay
	if payload['networkDhcpRelay']['domain']
      payload['networkDhcpRelay']['domain'].each do |k,v|
        payload['networkDhcpRelay'][k] = v
      end
      payload['networkDhcpRelay'].delete('domain')
    end

    @network_dhcp_relays_interface.setopts(options)

	serverIpAddresses = payload['networkDhcpRelay']['serverIpAddresses']
	if !serverIpAddresses.nil?
	  if !serverIpAddresses.kind_of?(Array)
	    payload['networkDhcpRelay']['serverIpAddresses'] = serverIpAddresses.to_s.split(',')
	  end
    end

    if options[:dry_run]
      print_dry_run @network_dhcp_relays_interface.dry.update_dhcp_relay(server['id'], dhcpRelay['id'], payload)
      return
    end

    json_response = @network_dhcp_relays_interface.update_dhcp_relay(server['id'], dhcpRelay['id'], payload)
    render_response(json_response, options, 'networkDhcpRelay') do
      print_green_success "\nUpdated Network DHCP Relay #{dhcpRelay['id']}\n"
      _get(server, dhcpRelay['id'], options)
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [dhcp_relay]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :quiet, :remote])
      opts.footer = "Delete a network dhcp relay.\n" +
        "[server] is required. This is the name or id of an existing network server.\n" +
        "[dhcp_relay] is required. This is the name or id of an existing network dhcp relay."
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

    if !server['type']['hasDhcpRelays']
      print_red_alert "DHCP Relays not supported for #{server['type']['name']}"
      return 1
    end

    dhcpRelay = find_dhcp_relay(server['id'], args[1])
    return 1 if dhcpRelay.nil?

    unless options[:yes] || ::Morpheus::Cli::OptionTypes::confirm("Are you sure you would like to remove the network dhcp relay '#{dhcpRelay['name']}' from server '#{server['name']}'?", options)
      return 9, "aborted command"
    end

    @network_dhcp_relays_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_dhcp_relays_interface.dry.delete_dhcp_relay(server['id'], dhcpRelay['id'])
      return
    end
    json_response = @network_dhcp_relays_interface.delete_dhcp_relay(server['id'], dhcpRelay['id'])
    render_response(json_response, options, 'networkDhcpRelay') do
      print_green_success "\nDeleted Network DHCP Relay #{dhcpRelay['name']}\n"
      _list(server, options)
    end
  end

  private

  def print_dhcp_relays(server, dhcpRelays)
    if dhcpRelays.count > 0
      cols = [:id]
      server['type']['dhcpRelayOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
        cols << option_type['fieldLabel']
      end
      rows = dhcpRelays.collect do |it|
        row = {
          id: it['id'],
          name: it['name'],
          serverIpAddresses: it['serverIpAddresses']
        }
        server['type']['dhcpRelayOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          row[option_type['fieldLabel']] = Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)
        end
        row
      end
      puts as_pretty_table(rows, cols)
    else
      println "No DHCP Relays\n"
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

  def find_dhcp_relay(server_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_dhcp_relay_by_id(server_id, val)
    else
      if dhcpRelay = find_dhcp_relay_by_name(server_id, val)
        return find_dhcp_relay_by_id(server_id, dhcpRelay['id'])
      end
    end
  end

  def find_dhcp_relay_by_id(server_id, dhcp_relay_id)
    begin
      json_response = @network_dhcp_relays_interface.get_dhcp_relay(server_id, dhcp_relay_id.to_i)
      return json_response['networkDhcpRelay']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network DHCP Relay not found by id #{dhcp_relay_id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_dhcp_relay_by_name(server_id, name)
    json_response = @network_dhcp_relays_interface.list_dhcp_relays(server_id, {phrase: name.to_s})
    dhcpRelays = json_response['networkDhcpRelays']
    if dhcpRelays.empty?
      print_red_alert "Network DHCP Relay not found by name #{name}"
      return nil
    elsif dhcpRelays.size > 1
      print_red_alert "#{dhcpRelays.size} network DHCP Relays found by name #{name}"
      rows = dhcpRelays.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return dhcpRelays[0]
    end
  end

end
