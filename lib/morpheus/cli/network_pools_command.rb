require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkPoolsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-pools'

  register_subcommands :list, :get, :add, :update, :remove #, :generate_pool
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_pools_interface = @api_client.network_pools
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
      opts.footer = "List network pools."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
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
        network_type_id = nil
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Pool Type', 'type' => 'select', 'optionSource' => 'networkPoolTypes', 'required' => true, 'description' => 'Choose a network pool type.'}], options, @api_client, {})
        network_type_id = v_prompt['type']
        if network_type_id.nil? || network_type_id.to_s.empty?
          print_red_alert "Pool Type not found by id '#{options['type']}'"
          return 1
        end
        payload['networkPool']['type'] = {'id' => network_type_id.to_i }

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
      opts.on('--type VALUE', String, "Type of network pool") do |val|
        options['description'] = val
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
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network pool.'}], options)
          # payload['networkPool']['name'] = v_prompt['name']
        end
        
        # Network Pool Type
        # network_type_id = nil
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Pool Type', 'type' => 'select', 'optionSource' => 'networkPoolTypes', 'required' => true, 'description' => 'Choose a network pool type.'}], options, @api_client, {})
        # network_type_id = v_prompt['type']
        # if network_type_id.nil? || network_type_id.to_s.empty?
        #   print_red_alert "Pool Type not found by id '#{options['type']}'"
        #   return 1
        # end
        # payload['networkPool']['type'] = {'id' => network_type_id.to_i }
        if options['type']
          payload['networkPool']['type'] = {'id' => options['type'].to_i }
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
      rows = network_pools.collect do |network_pool|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return network_pools[0]
    end
  end

end
