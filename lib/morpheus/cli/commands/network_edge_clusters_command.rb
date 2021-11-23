require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkEdgeClustersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::ProvisioningHelper
  include Morpheus::Cli::WhoamiHelper

  set_command_name :'network-edge-clusters'
  register_subcommands :list, :get, :update

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @account_interface = @api_client.accounts
    @network_edge_clusters_interface = @api_client.network_edge_clusters
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
      opts.footer = "List network edge clusters." + "\n" +
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
    @network_edge_clusters_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_edge_clusters_interface.dry.list_edge_clusters(server['id'])
      return
    end

    if server['type']['hasEdgeClusters']
      json_response = @network_edge_clusters_interface.list_edge_clusters(server['id'])
      render_response(json_response, options, 'networkEdgeClusters') do
        print_h1 "Network Edge Clusters For: #{server['name']}"
        print cyan
        print_edge_clusters(server, json_response['networkEdgeClusters'])
      end
    else
      print_red_alert "Edge Clusters not supported for #{server['type']['name']}"
    end
    print reset
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[server] [edge_cluster]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Display details on a network edge cluster." + "\n" +
        "[server] is required. This is the name or id of a network server.\n" +
        "[edge_cluster] is required. This is the id of a network edge cluster.\n"
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

  def _get(server, edge_cluster_id, options)
    @network_edge_clusters_interface.setopts(options)

    if options[:dry_run]
      if edge_cluster_id.to_s =~ /\A\d{1,}\Z/
        print_dry_run @network_edge_clusters_interface.dry.get_edge_cluster(server['id'], edge_cluster_id.to_i)
      else
        print_dry_run @network_edge_clusters_interface.dry.list_edge_clusters(server['id'], {name: edge_cluster_id})
      end
      return
    end

    if server['type']['hasEdgeClusters']
      edgeCluster = find_edge_cluster(server['id'], edge_cluster_id)

      return 1 if edgeCluster.nil?

      render_response({networkEdgeCluster: edgeCluster}, options, 'networkEdgeCluster') do
        print_h1 "Network Edge Cluster Details"
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

        server['type']['edgeClusterOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
          description_cols[option_type['fieldLabel']] = lambda {|it| Morpheus::Cli::OptionTypes.get_option_value(it, option_type, true)}
        end
        print_description_list(description_cols, edgeCluster)
      end
    else
      print_red_alert "Edge Clusters not supported for #{server['type']['name']}"
    end
    println reset
  end

  def update(args)
    options = {:options=>{}}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = subcommand_usage("[server] [edge_cluster]")
      opts.on( '--name NAME', "Name" ) do |val|
        params['name'] = val.to_s
      end
      opts.on("--description [TEXT]", String, "Description") do |val|
        params['description'] = val.to_s
      end
      add_perms_options(opts, options, ['plans', 'groups'])
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network edge cluster.\n" +
        "[server] is required. This is the name or id of an existing network server.\n" +
        "[edge_cluster] is required. This is the name or id of an existing network edge cluster."
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

    if !server['type']['hasEdgeClusters']
      print_red_alert "Edge Clusters not supported for #{server['type']['name']}"
      return 1
    end

    edgeCluster = find_edge_cluster(server['id'], args[1])
    return 1 if edgeCluster.nil?

    payload = parse_payload(options) || {'networkEdgeCluster' => params}
    payload['networkEdgeCluster'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options] && !payload['networkEdgeCluster'].nil?

    if !options[:visibility].nil?
      payload['networkEdgeCluster']['visibility'] = options[:visibility]
    end
    if !options[:tenants].nil?
      payload['networkEdgeCluster']['tenants'] = options[:tenants].collect {|id| {id: id.to_i}}
    end

    if payload['networkEdgeCluster'].empty?
      option_types = server['type']['edgeClusterOptionTypes'].sort_by {|it| it['displayOrder']}
      print_green_success "Nothing to update"
      println cyan
      print Morpheus::Cli::OptionTypes.display_option_types_help(
        option_types,
        {:include_context => true, :context_map => {'edgeCluster' => ''}, :color => cyan, :title => "Available Edge Cluster Options"}
      )
      exit 1
    end

    #payload = {'networkEdgeCluster' => edgeCluster.deep_merge(payload['networkEdgeCluster'])}

    @network_edge_clusters_interface.setopts(options)

    if options[:dry_run]
      print_dry_run @network_edge_clusters_interface.dry.update_edge_cluster(server['id'], edgeCluster['id'], payload)
      return
    end

    json_response = @network_edge_clusters_interface.update_edge_cluster(server['id'], edgeCluster['id'], payload)
    render_response(json_response, options, 'networkEdgeCluster') do
      print_green_success "\nUpdated Network Edge Cluster #{edgeCluster['id']}\n"
      _get(server, edgeCluster['id'], options)
    end
  end

  private

  def print_edge_clusters(server, edgeClusters)
    if edgeClusters.count > 0
      cols = [:id, :name, :description, :status]
      server['type']['edgeClusterOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
        cols << option_type['fieldLabel']
      end
      cols += [:visibility, :tenants] if is_master_account
      rows = edgeClusters.collect do |it|
        row = {
          id: it['id'],
          name: it['name'],
          description: it['description'],
          status: it['statusMessage'],
        }
        server['type']['edgeClusterOptionTypes'].sort_by {|it| it['displayOrder']}.each do |option_type|
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
      println "No Edge Clusters\n"
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

  def find_edge_cluster(server_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_edge_cluster_by_id(server_id, val)
    else
      if edgeCluster = find_edge_cluster_by_name(server_id, val)
        return find_edge_cluster_by_id(server_id, edgeCluster['id'])
      end
    end
  end

  def find_edge_cluster_by_id(server_id, edge_cluster_id)
    begin
      json_response = @network_edge_clusters_interface.get_edge_cluster(server_id, edge_cluster_id.to_i)
      return json_response['networkEdgeCluster']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Edge Cluster not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_edge_cluster_by_name(server_id, name)
    json_response = @network_edge_clusters_interface.list_edge_clusters(server_id, {phrase: name.to_s})
    edgeClusters = json_response['networkEdgeClusters']
    if edgeClusters.empty?
      print_red_alert "Network Edge Cluster not found by name #{name}"
      return nil
    elsif edgeClusters.size > 1
      print_red_alert "#{edgeClusters.size} network edge clusters found by name #{name}"
      rows = edgeClusters.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return edgeClusters[0]
    end
  end

end
