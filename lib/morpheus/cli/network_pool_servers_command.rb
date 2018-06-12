require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkPoolServersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-pool-servers'

  register_subcommands :list, :get, :add, :update, :remove
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_pool_servers_interface = @api_client.network_pool_servers
    @clouds_interface = @api_client.clouds
    @options_interface = @api_client.options
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List network pool servers."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      if options[:dry_run]
        print_dry_run @network_pool_servers_interface.dry.list(params)
        return
      end
      json_response = @network_pool_servers_interface.list(params)
      network_pool_servers = json_response["networkPoolServers"]
      if options[:json]
        puts as_json(json_response, options, "networkPoolServers")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkPoolServers")
        return 0
      elsif options[:csv]
        puts records_as_csv(network_pool_servers, options)
        return 0
      end
      title = "Morpheus Network Pool Servers"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if network_pool_servers.empty?
        print cyan,"No network pool servers found.",reset,"\n"
      else
        rows = network_pool_servers.collect {|network_pool_server| 
          row = {
            id: network_pool_server['id'],
            name: network_pool_server['name'],
            # description: network_pool_server['description'],
            type: network_pool_server['type'] ? network_pool_server['type']['name'] : '',
            pools: network_pool_server['pools'] ? network_pool_server['pools'].collect {|it| it['name'] }.uniq.join(', ') : '',
          }
          row
        }
        columns = [:id, :name, :type, :pools]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network pool server", :n_label => "network pool servers"})
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool-server]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network pool server." + "\n" +
                    "[network-pool-server] is required. This is the name or id of a network pool server."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-pool-server]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_pool_servers_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_pool_servers_interface.dry.list({name:args[0]})
        end
        return
      end
      network_pool_server = find_network_pool_server_by_name_or_id(args[0])
      return 1 if network_pool_server.nil?
      json_response = {'networkPoolServer' => network_pool_server}  # skip redundant request
      # json_response = @network_pool_servers_interface.get(network_pool_server['id'])
      network_pool_server = json_response['networkPoolServer']
      if options[:json]
        puts as_json(json_response, options, 'networkPoolServer')
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, 'networkPoolServer')
        return 0
      elsif options[:csv]
        puts records_as_csv([network_pool_server], options)
        return 0
      end
      print_h1 "Network Pool Server Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
        # "Service URL" => lambda {|it| it['serviceUrl'] : '' },
        "Pools" => lambda {|it| it['pools'] ? it['pools'].collect {|p| p['name'] }.uniq.join(', ') : '' },
      }
      print_description_list(description_cols, network_pool_server)
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def add(args)
    options = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on('--name VALUE', String, "Name for this network pool server") do |val|
        options['name'] = val
      end
      opts.on('--type VALUE', String, "Type of network pool server") do |val|
        options['type'] = val
      end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network pool server." + "\n" +
                    "[name] is required and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0-1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # support [name] as first argument
      if args[0]
        options['name'] = args[0]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkPoolServer' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['networkPoolServer'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkPoolServer']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network pool server.'}], options)
          payload['networkPoolServer']['name'] = v_prompt['name']
        end
        
        # Network Pool Server Type
        network_type_id = nil
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Pool Server Type', 'type' => 'select', 'optionSource' => 'networkPoolServerTypes', 'required' => true, 'description' => 'Choose a network pool server type.'}], options, @api_client, {})
        network_type_id = v_prompt['type']
        if network_type_id.nil? || network_type_id.to_s.empty?
          print_red_alert "Pool Server Type not found by id '#{options['type']}'"
          return 1
        end
        payload['networkPoolServer']['type'] = {'id' => network_type_id.to_i }

        # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']

      end

      
      if options[:dry_run]
        print_dry_run @network_pool_servers_interface.dry.create(payload)
        return
      end
      json_response = @network_pool_servers_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_pool_server = json_response['networkPoolServer']
        print_green_success "Added network pool server #{network_pool_server['name']}"
        get([network_pool_server['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool-server] [options]")
      opts.on('--name VALUE', String, "Name for this network pool server") do |val|
        options['name'] = val
      end
      opts.on('--type VALUE', String, "Type of network pool server") do |val|
        options['description'] = val
      end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network pool server." + "\n" +
                    "[network-pool-server] is required. This is the id of a network pool server."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network_pool_server = find_network_pool_server_by_name_or_id(args[0])
      return 1 if network_pool_server.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkPoolServer' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkPoolServer'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkPoolServer']['name'] = options['name']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network pool server.'}], options)
          # payload['networkPoolServer']['name'] = v_prompt['name']
        end
        
        # Network Pool Server Type
        # network_type_id = nil
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Pool Server Type', 'type' => 'select', 'optionSource' => 'networkPoolServerTypes', 'required' => true, 'description' => 'Choose a network pool server type.'}], options, @api_client, {})
        # network_type_id = v_prompt['type']
        # if network_type_id.nil? || network_type_id.to_s.empty?
        #   print_red_alert "Pool Server Type not found by id '#{options['type']}'"
        #   return 1
        # end
        # payload['networkPoolServer']['type'] = {'id' => network_type_id.to_i }
        if options['type']
          payload['networkPoolServer']['type'] = {'id' => options['type'].to_i }
        end

        # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']

      end

      if options[:dry_run]
        print_dry_run @network_pool_servers_interface.dry.update(network_pool_server["id"], payload)
        return
      end
      json_response = @network_pool_servers_interface.update(network_pool_server["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network_pool_server = json_response['networkPoolServer']
        print_green_success "Updated network pool server #{network_pool_server['name']}"
        get([network_pool_server['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool-server]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network pool server." + "\n" +
                    "[network-pool-server] is required. This is the name or id of a network pool server."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-pool-server]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network_pool_server = find_network_pool_server_by_name_or_id(args[0])
      return 1 if network_pool_server.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network pool server: #{network_pool_server['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @network_pool_servers_interface.dry.destroy(network_pool_server['id'])
        return 0
      end
      json_response = @network_pool_servers_interface.destroy(network_pool_server['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network pool server #{network_pool_server['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


 def find_network_pool_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_pool_server_by_id(val)
    else
      return find_network_pool_server_by_name(val)
    end
  end

  def find_network_pool_server_by_id(id)
    begin
      json_response = @network_pool_servers_interface.get(id.to_i)
      return json_response['networkPoolServer']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Pool Server not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_pool_server_by_name(name)
    json_response = @network_pool_servers_interface.list({name: name.to_s})
    network_pool_servers = json_response['networkPoolServers']
    if network_pool_servers.empty?
      print_red_alert "Network Pool Server not found by name #{name}"
      return nil
    elsif network_pool_servers.size > 1
      print_red_alert "#{network_pool_servers.size} network pool servers found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_pool_servers.collect do |network_pool_server|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return network_pool_servers[0]
    end
  end

end
