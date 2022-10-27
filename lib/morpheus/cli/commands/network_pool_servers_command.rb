require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkPoolServersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_description "View and manage network pool servers (IPAM integrations)"
  set_command_name :'network-pool-servers'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list_types, :get_type
  
  # RestCommand settings
  register_interfaces :network_pool_servers, :network_pool_server_types, :clouds, :options
  set_rest_has_type true
  # set_rest_type :network_pool_server_types

  def handle(args)
    handle_subcommand(args)
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

        # prompt options
        network_pool_server_type = @network_pool_servers_interface.get_type(network_type_id.to_i)['networkPoolServerType']
        option_result = Morpheus::Cli::OptionTypes.prompt(network_pool_server_type['optionTypes'], options[:options].deep_merge({:context_map => {'networkPoolServer' => ''}}), @api_client, {}, options[:no_prompt], true)
        payload['networkPoolServer'].deep_merge!(option_result)
      end

      @network_pool_servers_interface.setopts(options)
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
        _get(network_pool_server['id'], {}, options)
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
      @network_pool_servers_interface.setopts(options)
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
        _get(network_pool_server['id'], {}, options)
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
      @network_pool_servers_interface.setopts(options)
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

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      columns = rest_column_definitions(options)
      if record['credential'] && record['credential']['type'] != 'local'
        columns.delete("Username")
        columns.delete("Password")
      end
      columns.delete("Throttle Rate") if record['xxxxx'].to_s.empty?
      # columns.delete("Disable SSL SNI Verification") if record['ignoreSsl'].nil?
      columns.delete("Ignore SSL") if record['ignoreSsl'].nil?
      columns.delete("Network Filter") if record['networkFilter'].to_s.empty?
      columns.delete("Zone Filter") if record['zoneFilter'].to_s.empty?
      columns.delete("Tenant Match") if record['tenantMatch'].to_s.empty?
      columns.delete("Service Mode") if record['serviceMode'].to_s.empty?
      columns.delete("Extra Attributes") if record['config'].nil? || record['config']['extraAttributes'].to_s.empty?
      columns.delete("Enabled") if record['enabled'].nil?
      print_description_list(columns, record, options)
      # show Pools
      pools = record['pools']
      if pools && !pools.empty?
        print_h2 "Network Pools"
        print as_pretty_table(pools, [:id, :name], options)
      end
      print reset,"\n"
    end
  end

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
      rows = network_pool_servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_pool_servers[0]
    end
  end

end
