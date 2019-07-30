require 'rest_client'
require 'optparse'
require 'filesize'
require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/infrastructure_helper'

class Morpheus::Cli::NetworkDomainsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_name :'network-domains'

  register_subcommands :list, :get, :add, :update, :remove
  register_subcommands :list_records, :get_record, :add_record, :remove_record
  
  # set_default_subcommand :list
  
  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @network_domains_interface = @api_client.network_domains
    @network_domain_records_interface = @api_client.network_domain_records
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
      opts.footer = "List network domains."
    end
    optparse.parse!(args)
    connect(options)
    begin
      params.merge!(parse_list_options(options))
      @network_domains_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domains_interface.dry.list(params)
        return
      end
      json_response = @network_domains_interface.list(params)
      network_domains = json_response["networkDomains"]
      if options[:json]
        puts as_json(json_response, options, "networkDomains")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkDomains")
        return 0
      elsif options[:csv]
        puts records_as_csv(network_domains, options)
        return 0
      end
      title = "Morpheus Network Domains"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if network_domains.empty?
        print cyan,"No network domains found.",reset,"\n"
      else
        rows = network_domains.collect {|network_domain| 
          row = {
            id: network_domain['id'],
            name: network_domain['name'],
            description: network_domain['description'], 
            source: network_domain['refType'] ? "#{network_domain['refType']} #{network_domain['id']}" : '', # showReferenceName(refType, refId)
            domainController: network_domain['domainController'] ? 'Yes' : 'No', 
            visibility: network_domain['visibility'].to_s.capitalize, 
            tenant: network_domain['account'] ? network_domain['account']['name'] : '', 
            owner: network_domain['owner'] ? network_domain['owner']['name'] : '', 
          }
          row
        }
        columns = [:id, :name, :description, {:domainController => {:display_name => "DOMAIN CONTROLLER"} }, :visibility, :tenant]
        if options[:include_fields]
          columns = options[:include_fields]
          rows = network_domains
        end
        print cyan
        print as_pretty_table(rows, columns, options)
        print reset
        print_results_pagination(json_response, {:label => "network domain", :n_label => "network domains"})
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
      opts.banner = subcommand_usage("[network-domain]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network domain." + "\n" +
                    "[network-domain] is required. This is the name or id of a network domain."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-domain]\n#{optparse}"
      return 1
    end
    connect(options)
    begin
      @network_domains_interface.setopts(options)
      if options[:dry_run]
        if args[0].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_domains_interface.dry.get(args[0].to_i)
        else
          print_dry_run @network_domains_interface.dry.list({name:args[0]})
        end
        return
      end
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      json_response = {'networkDomain' => network_domain}  # skip redundant request
      # json_response = @network_domains_interface.get(network_domain['id'])
      network_domain = json_response['networkDomain']
      
      if options[:json]
        puts as_json(json_response, options, 'networkDomain')
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, 'networkDomain')
        return 0
      elsif options[:csv]
        puts records_as_csv([network_domain], options)
        return 0
      end
      print_h1 "Network Domain Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "Description" => lambda {|it| it['description'] },
        # "Source" => lambda {|it| it['refSource'] }, showReferenceName(refType, refId)
        "Domain Controller" => lambda {|it| it['domainController'] ? 'Yes' : 'No' },
        "Public Zone" => lambda {|it| it['publicZone'] ? 'Yes' : 'No' },
        "Domain Username" => lambda {|it| it['domainUsername'] },
        "Domain Password" => lambda {|it| it['domainPassword'] },
        "DC Server" => lambda {|it| it['dcServer'] },
        "OU Path" => lambda {|it| it['ouPath'] },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenant" => lambda {|it| it['account'] ? it['account']['name'] : '' },
      }
      print_description_list(description_cols, network_domain)
      
      # print_h2 "Domain Records"
      # print cyan
      # if network_domain['records']
      #   network_domain['records'].each do |r|
      #     puts " * #{r['name']}\t#{r['fqdn']}\t#{r['type']}\t#{r['ttl']}"
      #   end
      # end
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
      opts.on('--name VALUE', String, "Name for this network domain") do |val|
        options['name'] = val
      end
      opts.on('--description VALUE', String, "Description for this network domain") do |val|
        options['type'] = val
      end
      opts.on('--public-zone [on|off]', String, "Public Zone") do |val|
        options['publicZone'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--domain-controller [on|off]', String, "Join Domain Controller") do |val|
        options['domainController'] = val.to_s == 'on' || val.to_s == 'true'
      end
      opts.on('--domain-username VALUE', String, "Domain Username") do |val|
        options['domainUsername'] = val
      end
      opts.on('--domain-password VALUE', String, "Domain Password") do |val|
        options['domainPassword'] = val
      end
      opts.on('--dc-server VALUE', String, "DC Server") do |val|
        options['dcServer'] = val
      end
      opts.on('--ou-path VALUE', String, "OU Path") do |val|
        options['ouPath'] = val
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--tenant ID', String, "Tenant Account ID") do |val|
        options['tenant'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network domain." + "\n" +
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
          'networkDomain' => {
            # 'config' => {}
          }
        }
        
        # allow arbitrary -O options
        payload['networkDomain'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkDomain']['name'] = options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network domain.'}], options)
          payload['networkDomain']['name'] = v_prompt['name']
        end

        # Description
        if options['description']
          payload['networkDomain']['description'] = options['description']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false, 'description' => 'Description for this network domain.'}], options)
          payload['networkDomain']['description'] = v_prompt['description']
        end
        
        # Public Zone
        if options['publicZone'] != nil
          payload['networkDomain']['publicZone'] = options['publicZone']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'publicZone', 'fieldLabel' => 'Public Zone', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['publicZone'] = (v_prompt['publicZone'].to_s == 'on') unless v_prompt['publicZone'].nil?
        end

        # Domain Controller
        join_domain_controller = false
        if options['domainController'] != nil
          payload['networkDomain']['domainController'] = options['domainController']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'domainController', 'fieldLabel' => 'Join Domain Controller', 'type' => 'checkbox', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['domainController'] = (v_prompt['domainController'].to_s == 'on') unless v_prompt['domainController'].nil?
        end
        join_domain_controller = !!payload['networkDomain']['domainController']

        # Domain Username
        if options['domainUsername'] != nil
          payload['networkDomain']['domainUsername'] = options['domainUsername']
        elsif join_domain_controller
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'domainUsername', 'fieldLabel' => 'Domain Username', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['domainUsername'] = v_prompt['domainUsername'] unless v_prompt['domainUsername'].nil?
        end

        # Domain Password
        if options['domainPassword'] != nil
          payload['networkDomain']['domainPassword'] = options['domainPassword']
        elsif join_domain_controller
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'domainPassword', 'fieldLabel' => 'Domain Password', 'type' => 'password', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['domainPassword'] = v_prompt['domainPassword'] unless v_prompt['domainPassword'].nil?
        end
        
        # DC Server
        if options['dcServer'] != nil
          payload['networkDomain']['dcServer'] = options['dcServer']
        elsif join_domain_controller
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'dcServer', 'fieldLabel' => 'DC Server', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['dcServer'] = v_prompt['dcServer'] unless v_prompt['dcServer'].nil?
        end

        # OU Path
        if options['ouPath'] != nil
          payload['networkDomain']['ouPath'] = options['ouPath']
        elsif join_domain_controller
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ouPath', 'fieldLabel' => 'OU Path', 'type' => 'text', 'required' => false, 'description' => ''}], options)
          payload['networkDomain']['ouPath'] = v_prompt['ouPath'] unless v_prompt['ouPath'].nil?
        end

        # Visibility
        if options['visibility']
          payload['networkDomain']['visibility'] = options['visibility'].to_s.downcase
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'defaultValue' => 'private'}], options)
          payload['networkDomain']['visibility'] = v_prompt['visibility'].to_s.downcase
        end

        # Tenant
        if options['tenant']
          payload['networkDomain']['account'] = {'id' => options['tenant'].to_i}
        else
          begin
            available_accounts = @api_client.accounts.list({max:10000})['accounts'].collect {|it| {'name' => it['name'], 'value' => it['id'], 'id' => it['id']}}
            account_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'tenant', 'fieldLabel' => 'Tenant', 'type' => 'select', 'selectOptions' => available_accounts, 'required' => false, 'description' => 'Tenant'}], options)
            if account_prompt['tenant']
              payload['networkDomain']['account'] = {'id' => account_prompt['tenant']}
            end
          rescue
            puts "failed to load list of available tenants: #{ex.message}"
          end
        end

      end

      @network_domains_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domains_interface.dry.create(payload)
        return
      end
      json_response = @network_domains_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_domain = json_response['networkDomain']
        print_green_success "Added network domain #{network_domain['name']}"
        get([network_domain['id']])
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
      opts.banner = subcommand_usage("[network-domain] [options]")
      opts.on('--name VALUE', String, "Name for this network domain") do |val|
        options['name'] = val
      end
      opts.on('--type VALUE', String, "Type of network domain") do |val|
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
      opts.footer = "Update a network domain." + "\n" +
                    "[network-domain] is required. This is the id of a network domain."
    end
    optparse.parse!(args)
    if args.count != 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1 and got #{args.count}\n#{optparse}"
      return 1
    end
    connect(options)

    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkDomain' => {
          }
        }
        
        # allow arbitrary -O options
        payload['networkDomain'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        if options['name']
          payload['networkDomain']['name'] = options['name']
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network domain.'}], options)
          # payload['networkDomain']['name'] = v_prompt['name']
        end
        
        # Network Domain Type
        # network_type_id = nil
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Domain Type', 'type' => 'select', 'optionSource' => 'networkDomainTypes', 'required' => true, 'description' => 'Choose a network domain type.'}], options, @api_client, {})
        # network_type_id = v_prompt['type']
        # if network_type_id.nil? || network_type_id.to_s.empty?
        #   print_red_alert "Domain Type not found by id '#{options['type']}'"
        #   return 1
        # end
        # payload['networkDomain']['type'] = {'id' => network_type_id.to_i }
        if options['type']
          payload['networkDomain']['type'] = {'id' => options['type'].to_i }
        end

        # IP Ranges
        if ip_range_list
          ip_range_list = ip_range_list.collect {|range|
            # ugh, need to allow changing an existing range by id too
            if network_domain['ipRanges']
              existing_range = network_domain['ipRanges'].find {|r|
                range[:startAddress] == r['startAddress'] && range[:endAddress] == r['endAddress']
              }
              if existing_range
                range[:id] = existing_range['id']
              end
            end
            range
          }
          payload['networkDomain']['ipRanges'] = ip_range_list
        else
          # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ipRanges', 'fieldLabel' => 'IP Ranges', 'type' => 'text', 'required' => true, 'description' => 'IP Ranges in the domain, comma separated list of ranges in the format start-end.'}], options)
          # payload['networkDomain']['ipRanges'] = v_prompt['ipRanges'].to_s.split(",").collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq.collect {|it| 
          #   it
          # }
        end

      end
      @network_domains_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domains_interface.dry.update(network_domain["id"], payload)
        return
      end
      json_response = @network_domains_interface.update(network_domain["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        network_domain = json_response['networkDomain']
        print_green_success "Updated network domain #{network_domain['name']}"
        get([network_domain['id']])
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
      opts.banner = subcommand_usage("[network-domain]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network domain." + "\n" +
                    "[network-domain] is required. This is the name or id of a network domain."
    end
    optparse.parse!(args)

    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} missing argument: [network-domain]\n#{optparse}"
      return 1
    end

    connect(options)
    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the network domain: #{network_domain['name']}?")
        return 9, "aborted command"
      end
      @network_domains_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domains_interface.dry.destroy(network_domain['id'])
        return 0
      end
      json_response = @network_domains_interface.destroy(network_domain['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network domain #{network_domain['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def list_records(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-domain]")
      build_common_options(opts, options, [:list, :json, :yaml, :csv, :fields, :json, :dry_run, :remote])
      opts.footer = "List network domain records.\n" +
                    "[network-domain] is required. This is the name or id of a network domain."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      network_domain_id = network_domain['id']

      params.merge!(parse_list_options(options))
      @network_domain_records_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domain_records_interface.dry.list(network_domain_id, params)
        return
      end
      json_response = @network_domain_records_interface.list(network_domain_id, params)
      network_domain_records = json_response["networkDomainRecords"]
      if options[:json]
        puts as_json(json_response, options, "networkDomainRecords")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkDomainRecords")
        return 0
      elsif options[:csv]
        puts records_as_csv(network_domain_records, options)
        return 0
      end
      title = "Morpheus Network Domain Records"
      subtitles = []
      subtitles += parse_list_subtitles(options)
      print_h1 title, subtitles
      if network_domain_records.empty?
        print cyan,"No network domain records found.",reset,"\n"
      else
        columns = [
          {"ID" => lambda {|it| it['id'] } },
          {"NAME" => lambda {|it| it['name'] } },
          #{"FQDN" => lambda {|it| it['fqdn'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          # {"CONTENT" => lambda {|it| it['content'] } },
          {"CONTENT" => lambda {|it| it['content'].to_s.split.join(",") } },
          # {"COMMENT" => lambda {|it| it['comment'] } },
          #{"CREATED BY" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' } },
          #{"CREATED" => lambda {|it| format_local_dt(it['dateCreated']) } },
          #{"UPDATED" => lambda {|it| format_local_dt(it['lastUpdated']) } },
        ]
        if options[:include_fields]
          columns = options[:include_fields]
        end
        print as_pretty_table(network_domain_records, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get_record(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-domain] [record]")
      build_common_options(opts, options, [:query, :json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a network domain record.\n" +
                    "[network-domain] is required. This is the name or id of a network domain.\n" +
                    "[record] is required. This is the name or id of a network domain record."
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      network_domain_id = network_domain['id']

      params.merge!(parse_list_options(options))
      @network_domain_records_interface.setopts(options)
      if options[:dry_run]
        if args[1].to_s =~ /\A\d{1,}\Z/
          print_dry_run @network_domain_records_interface.dry.get(network_domain_id, args[1].to_i)
        else
          print_dry_run @network_domain_records_interface.dry.list(network_domain_id, {name:args[1]})
        end
        return
      end
      network_domain_record = find_network_domain_record_by_name_or_id(network_domain_id, args[1])
      return 1 if network_domain_record.nil?
      json_response = {'networkDomainRecord' => network_domain_record}  # skip redundant request
      # json_response = @network_domain_records_interface.get(network_domain_id, args[1])
      #network_domain_record = json_response['networkDomainRecord']
      if options[:json]
        puts as_json(json_response, options, "networkDomainRecord")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "networkDomainRecord")
        return 0
      elsif options[:csv]
        puts records_as_csv([network_domain_record], options)
        return 0
      end
      print_h1 "Network Domain Record Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => lambda {|it| it['name'] },
        "FQDN" => lambda {|it| it['fqdn'] },
        "Type" => lambda {|it| it['type'] },
        "Content" => lambda {|it| it['content'] },
        "Comment" => lambda {|it| it['Comment'] },
        "TTL" => lambda {|it| it['ttl'] },
        "Domain" => lambda {|it| network_domain['name'] },
        "Source" => lambda {|it| it['source'] },
        "Created By" => lambda {|it| it['createdBy'] ? it['createdBy']['username'] : '' },
        #"Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        #"Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
        #"Status" => lambda {|it| it['statusMessage'].to_s.empty? ? it['status'] : "#{it['status']} - #{it['statusMessage']}" },
      }
      print_description_list(description_cols, network_domain_record)

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def add_record(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-domain] [record]")
      opts.on('--name VALUE', String, "Name") do |val|
        options[:options]['name'] = val
      end
      opts.on('--type VALUE', String, "Domain Record Type. Default is 'A'") do |val|
        options[:options]['type'] = val
      end
      # opts.on('--fqdn VALUE', String, "FQDN") do |val|
      #   options[:options]['hostname'] = val
      # end
      opts.on('--content VALUE', String, "Content") do |val|
        options[:options]['content'] = val
      end
      opts.on('--comment VALUE', String, "Comment") do |val|
        options[:options]['comment'] = val
      end
      opts.on('--ttl SECONDS', String, "TTL in seconds. Default is 86400.") do |val|
        options[:options]['ttl'] = val
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :quiet, :remote])
      opts.footer = "Create a new network domain record." + "\n" +
                    "[network-domain] is required. This is the name or id of a network domain.\n" +
                    "[record] is required. This is the name of the domain record and can be passed as --name instead."
    end
    optparse.parse!(args)
    if args.count < 1 || args.count > 2
      raise_command_error "wrong number of arguments, expected 1-2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      network_domain_id = network_domain['id']

      # support [name] as first argument
      if args[1]
        options[:options]['name'] = args[1]
      end

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for network options
        payload = {
          'networkDomainRecord' => {
            #'networkDomain' => {'id' => network_domain['id']}
          }
        }
        
        # allow arbitrary -O options
        payload['networkDomainRecord'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

        # Name
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name of this domain record.'}], options[:options])
        payload['networkDomainRecord']['name'] = v_prompt['name'] unless v_prompt['name'].to_s.empty?

        # Type
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'content', 'fieldLabel' => 'Type', 'type' => 'select', 'required' => true, 'optionSource' => 'dnsRecordType', 'description' => 'Type for this domain record.', 'defaultValue' => 'A'}], options[:options], @api_client)
        payload['networkDomainRecord']['type'] = v_prompt['type'] unless v_prompt['type'].to_s.empty?

        # Content
        v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'content', 'fieldLabel' => 'Content', 'type' => 'textarea', 'required' => true, 'description' => 'Content for this domain record.'}], options[:options])
        payload['networkDomainRecord']['content'] = v_prompt['content'] unless v_prompt['content'].to_s.empty?

        # TTL
        if options[:options]['ttl'] == 'null'
          payload['networkDomainRecord']['ttl'] = nil
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'ttl', 'fieldLabel' => 'TTL', 'type' => 'text', 'required' => false, 'description' => 'TTL in seconds for this domain record. Default is 86400.'}], options[:options])
          payload['networkDomainRecord']['ttl'] = v_prompt['ttl'].to_i unless v_prompt['ttl'].to_s.empty?
        end

        # Comment
        # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'comment', 'fieldLabel' => 'Comment', 'type' => 'text', 'required' => true, 'description' => 'Comment for this domain record.'}], options[:options])
        # payload['networkDomainRecord']['comment'] = v_prompt['comment'] unless v_prompt['comment'].to_s.empty?

      end

      @network_domain_records_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domain_records_interface.dry.create(network_domain_id, payload)
        return
      end
      json_response = @network_domain_records_interface.create(network_domain_id, payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      elsif !options[:quiet]
        network_domain_record = json_response['networkDomainRecord']
        print_green_success "Added network domain record #{network_domain_record['name']}"
        get_record([network_domain['id'], network_domain_record['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove_record(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network-domain] [record]")
      build_common_options(opts, options, [:account, :auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Delete a network domain record." + "\n" +
                    "[network-domain] is required. This is the name or id of a network domain.\n" +
                    "[record] is required. This is the name or id of a network domain record."
    end
    optparse.parse!(args)
    if args.count != 2
      raise_command_error "wrong number of arguments, expected 2 and got (#{args.count}) #{args}\n#{optparse}"
    end
    connect(options)
    begin
      network_domain = find_network_domain_by_name_or_id(args[0])
      return 1 if network_domain.nil?
      network_domain_id = network_domain['id']

      network_domain_record = find_network_domain_record_by_name_or_id(network_domain_id, args[1])
      return 1 if network_domain_record.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the networkd domain record: #{network_domain_record['name']}?")
        return 9, "aborted command"
      end
      @network_domain_records_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @network_domain_records_interface.dry.destroy(network_domain['id'], network_domain_record['id'])
        return 0
      end
      json_response = @network_domain_records_interface.destroy(network_domain['id'], network_domain_record['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Removed network domain record #{network_domain_record['name']}"
        # list([])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  private


 def find_network_domain_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_domain_by_id(val)
    else
      return find_network_domain_by_name(val)
    end
  end

  def find_network_domain_by_id(id)
    begin
      json_response = @network_domains_interface.get(id.to_i)
      return json_response['networkDomain']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Domain not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_domain_by_name(name)
    json_response = @network_domains_interface.list({name: name.to_s})
    network_domains = json_response['networkDomains']
    if network_domains.empty?
      print_red_alert "Network Domain not found by name #{name}"
      return nil
    elsif network_domains.size > 1
      print_red_alert "#{network_domains.size} network domains found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_domains.collect do |network_domain|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_domains[0]
    end
  end

  def find_network_domain_record_by_name_or_id(network_domain_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_domain_record_by_id(network_domain_id, val)
    else
      return find_network_domain_record_by_name(network_domain_id, val)
    end
  end

  def find_network_domain_record_by_id(network_domain_id, id)
    begin
      json_response = @network_domain_records_interface.get(network_domain_id, id.to_i)
      return json_response['networkDomainRecord']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Network Domain Record not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_network_domain_record_by_name(network_domain_id, name)
    json_response = @network_domain_records_interface.list(network_domain_id, {name: name.to_s})
    network_domain_records = json_response['networkDomainRecords']
    if network_domain_records.empty?
      print_red_alert "Network Domain Record not found by name #{name}"
      return nil
    elsif network_domain_records.size > 1
      print_red_alert "#{network_domain_records.size} network domain records found by name #{name}"
      columns = [
        {"ID" => lambda {|it| it['id'] } },
        {"NAME" => lambda {|it| it['name'] } },
        #{"FQDN" => lambda {|it| it['fqdn'] } },
        {"TYPE" => lambda {|it| it['type'] } },
        {"CONTENT" => lambda {|it| it['content'] } }
      ]
      puts as_pretty_table(network_domain_records, columns, {color:red})
      return nil
    else
      return network_domain_records[0]
    end
  end

end
