require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkPoolsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-pools'

  register_subcommands :list, :get, :add, :update, :remove #, :generate_pool
  register_subcommands :list_ips, :get_ip, :add_ip, :update_ip, :remove_ip
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_pools_interface = @api_client.network_pools
    @network_pool_ips_interface = @api_client.network_pool_ips
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
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "List network pools."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @network_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pools_interface.dry.list(params)
        return
      end
      json_response = @network_pools_interface.list(params)
      network_pools = json_response["networkPools"]
      if options[:json]
        puts as_json(json_response, options, "networkPools")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkPools")
        return 0
      elsif options[:csv]
        puts records_as_csv(network_pools, options)
        return 0
      end
      title = "Morpheus Network Pools"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if network_pools.empty?
        print cyan,"No network pools found.",reset,"\n"
      else
        rows = network_pools.collect {|network_pool| 
          row = {
            id: network_pool['id'],
            # matching UI, but huh??
            name: !network_pool['displayName'].to_s.empty? ? network_pool['displayName'] : network_pool['name'],
            network: network_pool['name'], 
            # network: network_pool['network'] ? network_pool['network']['name'] : '',
            type: network_pool['type'] ? network_pool['type']['name'] : '',
            ipRanges: network_pool['ipRanges'] ? network_pool['ipRanges'].collect {|it| it['startAddress'].to_s + " - " + it['endAddress'].to_s }.uniq.join(', ') : '',
            total: ("#{network_pool['ipCount']}/#{network_pool['freeCount']}")
          }
          row
        }
        columns = [:id, :name, :network, :type, {:ipRanges => {:display_name => "IP RANGES"} }, {:total => {:display_name => "TOTAL/FREE IPs"} }]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network pool", :n_label => "network pools"})
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
      opts.banner = subcommand_usage("[network-pool]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network pool." + "\n" +
                    "[network-pool] is required. This is the name or id of a network pool."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-pool]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @network_pools_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_pools_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_pools_interface.dry.list({name:args[0]})
        end
        return
      end
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      json_response = {'networkPool' => network_pool}  # skip redundant request
      # json_response = @network_pools_interface.get(network_pool['id'])
      network_pool = json_response['networkPool']
      if options[:json]
        puts as_json(json_response, options, "networkPool")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkPool")
        return 0
      elsif options[:csv]
        puts records_as_csv([network_pool], options)
        return 0
      end
      print_h1 "Network Pool Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| !it['displayName'].to_s.empty? ? it['displayName'] : it['name'] },
        "Network" => lambda {|it| it['name'] },
        "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
        # "IP Ranges" => lambda {|it| it['ipRanges'] ? it['ipRanges'].collect {|r| r['startAddress'].to_s + " - " + r['endAddress'].to_s }.uniq.join(', ') : '' },
        "Total IPs" => lambda {|it| it['ipCount'] },
        "Free IPs" => lambda {|it| it['freeCount'] },
      }
      print_description_list(description_cols, network_pool)
      
      print_h2 "IP Ranges"
      print cyan
      if network_pool['ipRanges']
        network_pool['ipRanges'].each do |r|
          puts " * #{r['startAddress']} - #{r['endAddress']}"
        end
      end
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
      opts.on('--name VALUE', String, "Name for this network pool") do |val|
        options['name'] = val
      end
      opts.on('--type VALUE', String, "Type of network pool") do |val|
        options['type'] = val
      end
      opts.on('--ip-ranges LIST', Array, "IP Ranges, comma separated list IP ranges in the format start-end.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          ip_range_list = []
        else
          ip_range_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          ip_range_list = ip_range_list.collect {|it|
            range_parts = it.split("-")
            {startAddress: range_parts[0].to_s.strip, endAddress: range_parts[1].to_s.strip}
          }
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network pool." + "\n" +
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
          'networkPool' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['networkPool'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkPool']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network pool.'}], options)
          payload['networkPool']['name'] = v_prompt['name']
        end
        
        # Network Pool Type
        network_type_code = nil
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Pool Type', 'type' => 'select', 'optionSource' => 'networkPoolTypes', 'required' => true, 'description' => 'Choose a network pool type.'}], options, @api_client, {})
        network_type_code = v_prompt['type']
        if network_type_code.nil? || network_type_code.to_s.empty?
          print_red_alert "Pool Type not found by code '#{options['type']}'"
          return 1
        end
        # pre 4.1.1 expects ID
        if network_type_code.to_s =~ /\A\d{1,}\Z/
          payload['networkPool']['type'] = {'id' => network_type_code }
        else
          payload['networkPool']['type'] = {'code' => network_type_code }
        end
        # payload['networkPool']['type'] = network_type_code # this works too, simpler

        # IP Ranges
        if ip_range_list
          payload['networkPool']['ipRanges'] = ip_range_list
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ipRanges', 'fieldLabel' => 'IP Ranges', 'type' => 'text', 'required' => true, 'description' => 'IP Ranges in the pool, comma separated list of ranges in the format start-end.'}], options)
          ip_range_list = v_prompt['ipRanges'].to_s.split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          ip_range_list = ip_range_list.collect {|it|
            range_parts = it.split("-")
            range = {startAddress: range_parts[0].to_s.strip, endAddress: range_parts[1].to_s.strip}
            range
          }
          payload['networkPool']['ipRanges'] = ip_range_list
        end

      end

      @network_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pools_interface.dry.create(payload)
        return
      end
      json_response = @network_pools_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_pool = json_response['networkPool']
        print_green_success "Added network pool #{network_pool['name']}"
        get([network_pool['id']])
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
      opts.banner = subcommand_usage("[network-pool] [options]")
      opts.on('--name VALUE', String, "Name for this network pool") do |val|
        options['name'] = val
      end
      opts.on('--code VALUE', String, "Code") do |val|
        options['code'] = val
      end
      opts.on('--category VALUE', String, "Category") do |val|
        options['category'] = val
      end
      # todo all of these
      # internalId
      # externalId
      # dnsDomain
      # dnsSearchPath
      # hostPrefix
      # httpProxy
      # dnsServers
      # dnsSuffixList
      # dhcpServer
      # dhcpIp
      # gateway
      # netmask
      # subnetAddress
      # poolEnabled
      # tftpServer
      # bootFile
      opts.on('--ip-ranges LIST', Array, "IP Ranges, comma separated list IP ranges in the format start-end.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          ip_range_list = []
        else
          ip_range_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
          ip_range_list = ip_range_list.collect {|it|
            range_parts = it.split("-")
            {startAddress: range_parts[0].to_s.strip, endAddress: range_parts[1].to_s.strip}
          }
        end
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network pool." + "\n" +
                    "[network-pool] is required. This is the id of a network pool."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkPool' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkPool'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkPool']['name'] = options['name']
        end
        if options['category']
          payload['networkPool']['category'] = options['category']
        end
        if options['code']
          payload['networkPool']['code'] = options['code']
        end

        # IP Ranges
        if ip_range_list
          ip_range_list = ip_range_list.collect {|range|
            # ugh, need to allow changing an existing range by id too
            if network_pool['ipRanges']
              existing_range = network_pool['ipRanges'].find {|r|
                range[:startAddress] == r['startAddress'] && range[:endAddress] == r['endAddress']
              }
              if existing_range
                range[:id] = existing_range['id']
              end
            end
            range
          }
          payload['networkPool']['ipRanges'] = ip_range_list
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ipRanges', 'fieldLabel' => 'IP Ranges', 'type' => 'text', 'required' => true, 'description' => 'IP Ranges in the pool, comma separated list of ranges in the format start-end.'}], options)
          # payload['networkPool']['ipRanges'] = v_prompt['ipRanges'].to_s.split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| 
          #   it
          # }
        end

      end
      @network_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pools_interface.dry.update(network_pool["id"], payload)
        return
      end
      json_response = @network_pools_interface.update(network_pool["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network_pool = json_response['networkPool']
        print_green_success "Updated network pool #{network_pool['name']}"
        get([network_pool['id']])
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
      opts.banner = subcommand_usage("[network-pool]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network pool." + "\n" +
                    "[network-pool] is required. This is the name or id of a network pool."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-pool]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network pool: #{network_pool['name']}?")
        return 9, "aborted command"
      end
      @network_pools_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pools_interface.dry.destroy(network_pool['id'])
        return 0
      end
      json_response = @network_pools_interface.destroy(network_pool['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network pool #{network_pool['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_ips(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List network pool IP addresses.\n" +
                    "[network-pool] is required. This is the name or id of a network pool."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      network_pool_id = network_pool['id']

      params.merge!(parse_list_options(options))
      @network_pool_ips_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pool_ips_interface.dry.list(network_pool_id, params)
        return
      end
      json_response = @network_pool_ips_interface.list(network_pool_id, params)
      network_pool_ips = json_response["networkPoolIps"]
      if options[:json]
        puts as_json(json_response, options, "networkPoolIps")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkPoolIps")
        return 0
      elsif options[:csv]
        puts records_as_csv(network_pool_ips, options)
        return 0
      end
      title = "Morpheus Network Pool IPs"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if network_pool_ips.empty?
        print cyan,"No network pool IPs found.",reset,"\n"
      else
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"IP ADDRESS" => lambda {|it| it['ipAddress'] } },
          {"HOSTNAME" => lambda {|it| it['hostname'] } },
          {"TYPE" => lambda {|it| it['ipType'] } },
          #{"CREATED BY" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' } },
          {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
          {"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(network_pool_ips, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_ip(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool] [ip]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network pool IP address.\n" +
                    "[network-pool] is required. This is the name or id of a network pool.\n" +
                    "[ip] is required. This is the ip address or id of a network pool IP."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      network_pool_id = network_pool['id']

      params.merge!(parse_list_options(options))
      @network_pool_ips_interface.setopts(options)
      if options[:dry_run]
        if args[1].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_pool_ips_interface.dry.get(network_pool_id, args[1].to_i)
        else
          print_dry_run @network_pool_ips_interface.dry.list(network_pool_id, {ipAddress:args[1]})
        end
        return
      end
      network_pool_ip = find_network_pool_ip_by_address_or_id(network_pool_id, args[1])
      return 1 if network_pool_ip.nil?
      json_response = {'networkPoolIp' => network_pool_ip}  # skip redundant request
      # json_response = @network_pool_ips_interface.get(network_pool_id, args[1])
      #network_pool_ip = json_response['networkPoolIp']
      if options[:json]
        puts as_json(json_response, options, "networkPoolIp")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkPoolIp")
        return 0
      elsif options[:csv]
        puts records_as_csv([network_pool_ip], options)
        return 0
      end
      print_h1 "Network Pool IP Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "IP Address" => lambda {|it| it['ipAddress'] },
        "Hostname" => lambda {|it| it['hostname'] },
        "Type" => lambda {|it| it['ipType'] ? it['ipType'] : '' },
        # "Gateway" => lambda {|it| network_pool['gatewayAddress'] },
        # "Subnet Mask" => lambda {|it| network_pool['subnetMask'] },
        # "DNS Server" => lambda {|it| network_pool['dnsServer'] },
        "Pool" => lambda {|it| network_pool['name'] },
        #"Pool" => lambda {|it| it['networkPool'] ? it['networkPool']['name'] : '' },
        "Interface" => lambda {|it| network_pool['interfaceName'] },
        "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
        "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
      }
      print_description_list(description_cols, network_pool_ip)

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_ip(args)
    options = {}
    params = {}
    next_free_ip = false
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool] [ip] [--next]")
      opts.on('--ip-address VALUE', String, "IP Address for this network pool IP") do |val|
        options[:options]['ipAddress'] = val
      end
      opts.on('--next-free-ip', '--next-free-ip', "Use the next available ip address. This can be used instead of specifying an ip address") do
        next_free_ip = true
      end
      opts.on('--hostname VALUE', String, "Hostname for this network pool IP") do |val|
        options[:options]['hostname'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network pool IP." + "\n" +
                    "[network-pool] is required. This is the name or id of a network pool.\n" +
                    "[ip] is required or --next-free-ip to use the next available address instead."
    end
    optparse.parse!(args)
    if next_free_ip
      verify_args!(args:args, count:1, optparse:optparse)
    else
      verify_args!(args:args, min:1, max:2, optparse:optparse)
    end
    connect(options)
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      network_pool_id = network_pool['id']

      # support [ip] as first argument
      if args[1]
        options[:options]['ipAddress'] = args[1]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkPoolIp' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkPoolIp'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # IP Address
        unless next_free_ip
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ipAddress', 'fieldLabel' => 'IP Address', 'type' => 'text', 'required' => true, 'description' => 'IP Address for this network pool IP.'}], options[:options])
          payload['networkPoolIp']['ipAddress'] = v_prompt['ipAddress'] unless v_prompt['ipAddress'].to_s.empty?
        end

        # Hostname
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'hostname', 'fieldLabel' => 'Hostname', 'type' => 'text', 'required' => true, 'description' => 'Hostname for this network pool IP.'}], options[:options])
        payload['networkPoolIp']['hostname'] = v_prompt['hostname'] unless v_prompt['hostname'].to_s.empty?

      end

      @network_pool_ips_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pool_ips_interface.dry.create(network_pool_id, payload)
        return
      end
      json_response = @network_pool_ips_interface.create(network_pool_id, payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_pool_ip = json_response['networkPoolIp']
        print_green_success "Added network pool IP #{network_pool_ip['ipAddress']}"
        get_ip([network_pool['id'], network_pool_ip['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update_ip(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool] [ip] [options]")
      opts.on('--hostname VALUE', String, "Hostname for this network pool IP") do |val|
        options[:options]['hostname'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Update a network pool IP." + "\n" +
                    "[network-pool] is required. This is the name or id of a network pool.\n" +
                    "[ip] is required. This is the ip address or id of a network pool IP."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      network_pool_id = network_pool['id']

      network_pool_ip = find_network_pool_ip_by_address_or_id(network_pool_id, args[1])
      return 1 if network_pool_ip.nil?

      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkPoolIp' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkPoolIp'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        if payload['networkPoolIp'].empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

      end

      @network_pool_ips_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pool_ips_interface.dry.update(network_pool_id, network_pool_ip['id'], payload)
        return
      end
      json_response = @network_pool_ips_interface.update(network_pool_id, network_pool_ip['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_pool_ip = json_response['networkPoolIp']
        print_green_success "Updated network pool IP #{network_pool_ip['ipAddress']}"
        get_ip([network_pool['id'], network_pool_ip['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_ip(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-pool] [ip]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network pool IP." + "\n" +
                    "[network-pool] is required. This is the name or id of a network pool.\n" +
                    "[ip] is required. This is the ip address or id of a network pool IP."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network_pool = find_network_pool_by_name_or_id(args[0])
      return 1 if network_pool.nil?
      network_pool_id = network_pool['id']

      network_pool_ip = find_network_pool_ip_by_address_or_id(network_pool_id, args[1])
      return 1 if network_pool_ip.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network pool IP: #{network_pool_ip['ipAddress']} (#{network_pool_ip['hostname']})?")
        return 9, "aborted command"
      end
      @network_pool_ips_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_pool_ips_interface.dry.destroy(network_pool['id'], network_pool_ip['id'])
        return 0
      end
      json_response = @network_pool_ips_interface.destroy(network_pool['id'], network_pool_ip['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network pool IP #{network_pool_ip['ipAddress']} (#{network_pool_ip['hostname']})"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


  def find_network_pool_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_pool_by_id(val)
    else
      return find_network_pool_by_name(val)
    end
  end

  def find_network_pool_by_id(id)
    begin
      json_response = @network_pools_interface.get(id.to_i)
      return json_response['networkPool']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Pool not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_pool_by_name(name)
    json_response = @network_pools_interface.list({name: name.to_s})
    network_pools = json_response['networkPools']
    if network_pools.empty?
      print_red_alert "Network Pool not found by name #{name}"
      return nil
    elsif network_pools.size > 1
      print_red_alert "#{network_pools.size} network pools found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_pools.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_pools[0]
    end
  end

  def find_network_pool_ip_by_address_or_id(network_pool_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_pool_ip_by_id(network_pool_id, val)
    else
      return find_network_pool_ip_by_address(network_pool_id, val)
    end
  end

  def find_network_pool_ip_by_id(network_pool_id, id)
    begin
      json_response = @network_pool_ips_interface.get(network_pool_id, id.to_i)
      return json_response['networkPoolIp']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Pool IP not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_pool_ip_by_address(network_pool_id, address)
    json_response = @network_pool_ips_interface.list(network_pool_id, {ipAddress: address.to_s})
    network_pool_ips = json_response['networkPoolIps']
    if network_pool_ips.empty?
      print_red_alert "Network Pool IP not found by address #{address}"
      return nil
    elsif network_pool_ips.size > 1
      print_red_alert "#{network_pool_ips.size} network pool IPs found by address #{address}"
      columns = [
        {"ID" => lambda {|it| it['id'] } },
        {"IP ADDRESS" => lambda {|it| it['ipAddress'] } },
        {"HOSTNAME" => lambda {|it| it['hostname'] } },
        {"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } }
      ]
      puts as_pretty_table(network_pool_ips, columns, {color:red})
      return nil
    else
      return network_pool_ips[0]
    end
  end

end
