require 'rest_client'
require 'optparse'
require 'filesize'
require 'table_print'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkProxiesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-proxies'

  register_subcommands :list, :get, :add, :update, :remove #, :generate_proxy
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_proxies_interface = @api_client.network_proxies
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
      opts.footer = "List network proxies."
    end
    optparse.parse!(args)
    connect(options)
    begin
      [:phrase, :offset, :max, :sort, :direction].each do |k|
        params[k] = options[k] unless options[k].nil?
      end
      if options[:dry_run]
        print_dry_run @network_proxies_interface.dry.list(params)
        return
      end
      json_response = @network_proxies_interface.list(params)
      network_proxies = json_response["networkProxies"]
      if options[:include_fields]
        json_response = {"networkProxies" => filter_data(network_proxies, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv(network_proxies, options)
        return 0
      end
      title = "Morpheus Network Proxies"
      subtitles = []
      if params[:phrase]
        subtitles << "Search: #{params[:phrase]}".strip
      end
      print_h1 title, subtitles
      if network_proxies.empty?
        print cyan,"No network proxies found.",reset,"\n"
      else
        rows = network_proxies.collect {|network_proxy| 
          row = {
            id: network_proxy['id'],
            name: network_proxy['name'], 
            host: network_proxy['proxyHost'], 
            port: network_proxy['proxyPort'], 
            visibility: network_proxy['visibility'].to_s.capitalize, 
            tenant: network_proxy['account'] ? network_proxy['account']['name'] : '', 
            owner: network_proxy['owner'] ? network_proxy['owner']['name'] : '', 
          }
          row
        }
        columns = [:id, :name, :host, :port, :visibility, :tenant]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network proxy", :n_label => "network proxies"})
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
      opts.banner = subcommand_usage("[network-proxy]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network proxy." + "\n" +
                    "[network-proxy] is required. This is the name or id of a network proxy."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-proxy]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_proxies_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_proxies_interface.dry.list({name:args[0]})
        end
        return
      end
      network_proxy = find_network_proxy_by_name_or_id(args[0])
      return 1 if network_proxy.nil?
      json_response = {'networkProxy' => network_proxy}  # skip redundant request
      # json_response = @network_proxies_interface.get(network_proxy['id'])
      network_proxy = json_response['networkProxy']
      if options[:include_fields]
        json_response = {'networkProxy' => filter_data(network_proxy, options[:include_fields]) }
      end
      if options[:json]
        puts as_json(json_response, options)
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options)
        return 0
      elsif options[:csv]
        puts records_as_csv([network_proxy], options)
        return 0
      end
      print_h1 "Network Proxy Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "Proxy Host" => lambda {|it| it['proxyHost'] },
        "Proxy Port" => lambda {|it| it['proxyPort'] },
        "Proxy Username" => lambda {|it| it['proxyUser'] },
        "Proxy Password" => lambda {|it| it['proxyPassword'] }, # masked
        "Proxy Domain" => lambda {|it| it['proxyDomain'] },
        "Proxy Workstation" => lambda {|it| it['proxyWorkstation'] },
        "Proxy Host" => lambda {|it| it['proxyHost'] },
        "Proxy Host" => lambda {|it| it['proxyHost'] },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      }
      print_description_list(description_cols, network_proxy)
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
      opts.on('--name VALUE', String, "Name for this network proxy") do |val|
        options['name'] = val
      end
      opts.on('--proxy-host VALUE', String, "Proxy Host") do |val|
        options['proxyHost'] = val
      end
      opts.on('--proxy-port VALUE', String, "Proxy Port") do |val|
        options['proxyPort'] = val
      end
      opts.on('--proxy-user VALUE', String, "Proxy User") do |val|
        options['proxyUser'] = val
      end
      opts.on('--proxy-password VALUE', String, "Proxy Password") do |val|
        options['proxyPassword'] = val
      end
      opts.on('--proxy-domain VALUE', String, "Proxy Domain") do |val|
        options['proxyDomain'] = val
      end
      opts.on('--proxy-workstation VALUE', String, "Proxy Workstation") do |val|
        options['proxyWorkstation'] = val
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--tenant ID', String, "Tenant Account ID") do |val|
        options['tenant'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network proxy." + "\n" +
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
          'networkProxy' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['networkProxy'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkProxy']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network proxy.'}], options)
          payload['networkProxy']['name'] = v_prompt['name']
        end
        
        # Proxy Host
        if options['proxyHost'] != nil
          payload['networkProxy']['proxyHost'] = options['proxyHost']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyHost', 'fieldLabel' => 'Proxy Host', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyHost'] = v_prompt['proxyHost'] unless v_prompt['proxyHost'].nil?
        end

        # Proxy Port
        if options['proxyPort'] != nil
          payload['networkProxy']['proxyPort'] = options['proxyPort']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyPort', 'fieldLabel' => 'Proxy Port', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyPort'] = v_prompt['proxyPort'] unless v_prompt['proxyPort'].nil?
        end

        # Proxy Username
        if options['proxyUser'] != nil
          payload['networkProxy']['proxyUser'] = options['proxyUser']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyUser', 'fieldLabel' => 'Proxy Username', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyUser'] = v_prompt['proxyUser'] unless v_prompt['proxyUser'].nil?
        end

        # Proxy Password
        if options['proxyPassword'] != nil
          payload['networkProxy']['proxyPassword'] = options['proxyPassword']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyPassword', 'fieldLabel' => 'Proxy Password', 'type' => 'password', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyPassword'] = v_prompt['proxyPassword'] unless v_prompt['proxyPassword'].nil?
        end

        # Proxy Domain
        if options['proxyDomain'] != nil
          payload['networkProxy']['proxyDomain'] = options['proxyDomain']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyDomain', 'fieldLabel' => 'Proxy Domain', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyDomain'] = v_prompt['proxyDomain'] unless v_prompt['proxyDomain'].nil?
        end

        # Proxy Workstation
        if options['proxyWorkstation'] != nil
          payload['networkProxy']['proxyWorkstation'] = options['proxyWorkstation']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyWorkstation', 'fieldLabel' => 'Proxy Workstation', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkProxy']['proxyWorkstation'] = v_prompt['proxyWorkstation'] unless v_prompt['proxyWorkstation'].nil?
        end

        # Visibility
        if options['visibility']
          payload['networkProxy']['visibility'] = options['visibility'].to_s.downcase
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'defaultValue' => 'private'}], options)
          payload['networkProxy']['visibility'] = v_prompt['visibility'].to_s.downcase
        end

        # Tenant
        if options['tenant']
          payload['networkProxy']['account'] = {'id' => options['tenant'].to_i}
        else
          begin
            available_accounts = @api_client.accounts.list({max:10000})['accounts'].collect {|it| {'name' => it['name'], 'value' => it['id'], 'id' => it['id']}}
            account_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'selectOptions' => available_accounts, 'required' => false, 'description' => 'Tenant'}], options)
            if account_prompt['tenant']
              payload['networkProxy']['account'] = {'id' => account_prompt['tenant']}
            end
          rescue
            puts "failed to load list of available tenants: #{ex.message}"
          end
        end

      end

      
      if options[:dry_run]
        print_dry_run @network_proxies_interface.dry.create(payload)
        return
      end
      json_response = @network_proxies_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_proxy = json_response['networkProxy']
        print_green_success "Added network proxy #{network_proxy['name']}"
        get([network_proxy['id']])
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
      opts.banner = subcommand_usage("[network-proxy] [options]")
      opts.on('--name VALUE', String, "Name for this network proxy") do |val|
        options['name'] = val
      end
      opts.on('--proxy-host VALUE', String, "Proxy Host") do |val|
        options['proxyHost'] = val
      end
      opts.on('--proxy-port VALUE', String, "Proxy Port") do |val|
        options['proxyPort'] = val
      end
      opts.on('--proxy-user VALUE', String, "Proxy User") do |val|
        options['proxyUser'] = val
      end
      opts.on('--proxy-password VALUE', String, "Proxy Password") do |val|
        options['proxyPassword'] = val
      end
      opts.on('--proxy-domain VALUE', String, "Proxy Domain") do |val|
        options['proxyDomain'] = val
      end
      opts.on('--proxy-workstation VALUE', String, "Proxy Workstation") do |val|
        options['proxyWorkstation'] = val
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--tenant ID', String, "Tenant Account ID") do |val|
        options['tenant'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a network proxy." + "\n" +
                    "[network-proxy] is required. This is the id of a network proxy."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network_proxy = find_network_proxy_by_name_or_id(args[0])
      return 1 if network_proxy.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkProxy' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkProxy'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkProxy']['name'] = options['name']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network proxy.'}], options)
          # payload['networkProxy']['name'] = v_prompt['name']
        end
        
        # Proxy Host
        if options['proxyHost'] != nil
          payload['networkProxy']['proxyHost'] = options['proxyHost']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyHost', 'fieldLabel' => 'Proxy Host', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyHost'] = v_prompt['proxyHost'] unless v_prompt['proxyHost'].nil?
        end

        # Proxy Port
        if options['proxyPort'] != nil
          payload['networkProxy']['proxyPort'] = options['proxyPort']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyPort', 'fieldLabel' => 'Proxy Port', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyPort'] = v_prompt['proxyPort'] unless v_prompt['proxyPort'].nil?
        end

        # Proxy Username
        if options['proxyUser'] != nil
          payload['networkProxy']['proxyUser'] = options['proxyUser']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyUser', 'fieldLabel' => 'Proxy Username', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyUser'] = v_prompt['proxyUser'] unless v_prompt['proxyUser'].nil?
        end

        # Proxy Password
        if options['proxyPassword'] != nil
          payload['networkProxy']['proxyPassword'] = options['proxyPassword']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyPassword', 'fieldLabel' => 'Proxy Password', 'type' => 'password', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyPassword'] = v_prompt['proxyPassword'] unless v_prompt['proxyPassword'].nil?
        end

        # Proxy Domain
        if options['proxyDomain'] != nil
          payload['networkProxy']['proxyDomain'] = options['proxyDomain']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyDomain', 'fieldLabel' => 'Proxy Domain', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyDomain'] = v_prompt['proxyDomain'] unless v_prompt['proxyDomain'].nil?
        end

        # Proxy Workstation
        if options['proxyWorkstation'] != nil
          payload['networkProxy']['proxyWorkstation'] = options['proxyWorkstation']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'proxyWorkstation', 'fieldLabel' => 'Proxy Workstation', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          # payload['networkProxy']['proxyWorkstation'] = v_prompt['proxyWorkstation'] unless v_prompt['proxyWorkstation'].nil?
        end

        # Visibility
        if options['visibility']
          payload['networkProxy']['visibility'] = options['visibility'].to_s.downcase
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'defaultValue' => 'private'}], options)
          # payload['networkProxy']['visibility'] = v_prompt['visibility'].to_s.downcase
        end

        # Tenant
        if options['tenant']
          payload['networkProxy']['account'] = {'id' => options['tenant'].to_i}
        else
          # begin
          #   available_accounts = @api_client.accounts.list({max:10000})['accounts'].collect {|it| {'name' => it['name'], 'value' => it['id'], 'id' => it['id']}}
          #   account_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'selectOptions' => available_accounts, 'required' => false, 'description' => 'Tenant'}], options)
          #   if account_prompt['tenant']
          #     payload['networkProxy']['account'] = {'id' => account_prompt['tenant']}
          #   end
          # rescue
          #   puts "failed to load list of available tenants: #{ex.message}"
          # end
        end

      end

      if options[:dry_run]
        print_dry_run @network_proxies_interface.dry.update(network_proxy["id"], payload)
        return
      end
      json_response = @network_proxies_interface.update(network_proxy["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network_proxy = json_response['networkProxy']
        print_green_success "Updated network proxy #{network_proxy['name']}"
        get([network_proxy['id']])
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
      opts.banner = subcommand_usage("[network-proxy]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network proxy." + "\n" +
                    "[network-proxy] is required. This is the name or id of a network proxy."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-proxy]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network_proxy = find_network_proxy_by_name_or_id(args[0])
      return 1 if network_proxy.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network proxy: #{network_proxy['name']}?")
        return 9, "aborted command"
      end
      if options[:dry_run]
        print_dry_run @network_proxies_interface.dry.destroy(network_proxy['id'])
        return 0
      end
      json_response = @network_proxies_interface.destroy(network_proxy['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network proxy #{network_proxy['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


 def find_network_proxy_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_proxy_by_id(val)
    else
      return find_network_proxy_by_name(val)
    end
  end

  def find_network_proxy_by_id(id)
    begin
      json_response = @network_proxies_interface.get(id.to_i)
      return json_response['networkProxy']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Proxy not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_proxy_by_name(name)
    json_response = @network_proxies_interface.list({name: name.to_s})
    network_proxies = json_response['networkProxies']
    if network_proxies.empty?
      print_red_alert "Network Proxy not found by name #{name}"
      return nil
    elsif network_proxies.size > 1
      print_red_alert "#{network_proxies.size} network proxies found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_proxies.collect do |network_proxy|
        {id: it['id'], name: it['name']}
      end
      print red
      tp rows, [:id, :name]
      print reset,"\n"
      return nil
    else
      return network_proxies[0]
    end
  end

end
