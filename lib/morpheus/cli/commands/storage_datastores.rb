require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageDatastores
  include Morpheus::Cli::CliCommand

  register_subcommands :list, :add, :update, :get

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @storage_datastore_interface = @api_client.storage_datastores
    @cloud_datastores_interface = @api_client.cloud_datastores
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}  

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List Datastores."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    begin
      params.merge!(parse_list_options(options))
      
      @storage_datastore_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_datastore_interface.dry.list(params)
        return 0
      end

      json_response = @storage_datastore_interface.list(params)
      render_response(json_response, options, 'datastores') do
        datastores = json_response['datastores']
        title = "Storage Datastores"  
        print_h1 title
        if datastores.empty?
          print cyan,"No datastores found.",reset,"\n"
        else          
          columns = datastores_list_column_definitions(options).upcase_keys!
          print as_pretty_table(datastores, columns, options)
          print_results_pagination(json_response)
        end
        print reset,"\n"
      end
      return 0, nil
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def datastores_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name'
    }
  end

  def add(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name] [options]")
      build_common_options(opts, options, [:options, :payload, :json, :yaml, :dry_run, :quiet])
      opts.on( '-n', '--name NAME', "Name" ) do |val|
        options['name'] = val
      end
      opts.on( '-t', '--type DATASTORE_TYPE', "Datastore Type" ) do |val|
        options['datastoreType'] = val
      end
      opts.on( '-c', '--cloud DATASTORE_CLOUD', "Datastore Cloud" ) do |val|
        options['cloud'] = val
      end
      opts.footer = "Create a new Datastore.\n" +
                    "[name] is required. This is the name of the new datastore. It may also be passed as --name or inside your config."
    end
    optparse.parse!(args)
    if args.count > 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "#{command_name} add expects 0-1 arguments and received #{args.count}: #{args}\n#{optparse}"
      return 1
    end
    # allow name as first argument
    if args[0] # && !options[:name]
      options[:name] = args[0]
    end
    connect(options)
    begin
      options[:options] ||= {}
      passed_options = (options[:options] || {}).reject {|k,v| k.is_a?(Symbol) }
      payload = {}
      if options[:payload]
        # payload is from parsed json|yaml files or arguments.
        payload = options[:payload]
        # merge -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?
        # support some options on top of --payload
        [:name, :description, :environment].each do |k|
          if options.key?(k)
            payload[k.to_s] = options[k]
          end
        end
      else
        # prompt for payload
        payload = {}
        # merge -O options
        payload.deep_merge!(passed_options) unless passed_options.empty?

         # Name
        if passed_options['name']
          payload['name'] = passed_options['name']
        else
          v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Enter a name for this archive bucket.'}], options, @api_client)
          payload['name'] = v_prompt['name']
        end

        #Datastore Type
        if passed_options['datastoreType']
          payload['datastoreType'] = passed_options['datastoreType']
        else
          payload['datastoreType'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'datastoreType', 'fieldLabel' => 'Type', 'type' => 'select', 'required' => true, 'optionSource' => 'datastoreTypes'}], options[:options], @api_client)['datastoreType']
        end

        if passed_options['cloud']
          zone = passed_options['cloud']
        else
          zone = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'zone', 'fieldLabel' => 'Cloud', 'type' => 'select', 'required' => true, 'optionSource' => 'cloudsForDatastores'}], options[:options], @api_client)['zone']
        end

        if zone
          payload['refType'] = 'ComputeZone'
          payload['refId'] = zone
        end
        
        option_types = load_option_types_for_datastore_type(payload['datastoreType'])

        values = Morpheus::Cli::OptionTypes.prompt(option_types, options[:options], @api_client)
        if values['domain']
          payload.merge!(values['domain']) if values['domain'].is_a?(Hash)
        end
        if values['config']
          payload['config'] = {}
          payload['config'].merge!(values['config']) if values['config'].is_a?(Hash)
        end

        @storage_datastore_interface.setopts(options)
        if options[:dry_run]
          print_dry_run @storage_datastore_interface.dry.create({'datastore' => payload})
          return
        end
        json_response = @storage_datastore_interface.create({'datastore' => payload})
        datastore = json_response['datastore']
        if options[:json]
          print JSON.pretty_generate(json_response),"\n"
        elsif !options[:quiet]
          datastore = json_response['datastore']
          print_green_success "Datastore #{datastore['name']} created"
          #get([datastore['id']])
        end
      end
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def get(args)
    datastore_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[datastore]")
      build_common_options(opts, options, [:json, :yaml, :csv, :fields, :dry_run, :remote])
      opts.footer = "Get details about a datastore." + "\n" +
                    "[datastore] is required. This is the name or id of a datastore."
    end
    optparse.parse!(args)
    if args.count == 1
      datastore_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)
    begin
      @storage_datastore_interface.setopts(options)
      if options[:dry_run]
        if datastore_id.to_s =~ /\A\d{1,}\Z/
          print_dry_run @storage_datastore_interface.dry.get(datastore_id.to_i)
        else
          print_dry_run @storage_datastore_interface.dry.list({name:datastore_id})
        end
        return
      end
      datastore = find_datastore_by_name_or_id(datastore_id)
      return 1 if datastore.nil?
      json_response = {'datastore' => datastore}  # skip redundant request
      # json_response = @datastores_interface.get(datastore['id'])
      datastore = json_response['datastore']
      if options[:json]
        puts as_json(json_response, options, "datastore")
        return 0
      elsif options[:yaml]
        puts as_yaml(json_response, options, "datastore")
        return 0
      elsif options[:csv]
        puts records_as_csv([datastore], options)
        return 0
      end
      print_h1 "Datastore Details"
      print cyan
      description_cols = {
        "ID" => 'id',
        "Name" => 'name',
        "Type" => lambda {|it| it['type'].to_s.capitalize },
        "Cloud" => lambda {|it| it['zone'] ? it['zone']['name'] : '' },
        "Capacity" => lambda {|it| it['freeSpace'] ? Filesize.from("#{it['freeSpace']} B").pretty.strip : "Unknown" },
        "Online" => lambda {|it| format_boolean(it['online']) },
        "Active" => lambda {|it| format_boolean(it['active']) },
        "Visibility" => lambda {|it| it['visibility'].to_s.capitalize },
        "Tenants" => lambda {|it| it['tenants'] ? it['tenants'].collect {|it| it['name'] }.uniq.join(', ') : '' },
        # "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : '' },
      }
      print_description_list(description_cols, datastore)

      if datastore['resourcePermission'].nil?
        print "\n", "No group access found", "\n"
      else
        print_h2 "Group Access"
        rows = []
        if datastore['resourcePermission']['all']
          rows.push({"name" => 'All'})
        end
        if datastore['resourcePermission']['sites']
          datastore['resourcePermission']['sites'].each do |site|
            rows.push(site)
          end
        end
        rows = rows.collect do |site|
          # {group: site['name'], default: site['default'] ? 'Yes' : ''}
          {group: site['name']}
        end
        # columns = [:group, :default]
        columns = [:group]
        print cyan
        print as_pretty_table(rows, columns)
      end

      if datastore['tenants'].nil? || datastore['tenants'].nil?
        #print "\n", "No tenant permissions found", "\n"
      else
        print_h2 "Tenant Permissions"
        rows = []
        rows = datastore['tenants'] || []
        tenant_columns = {
          "TENANT" => 'name',
          #"DEFAULT" => lambda {|it| format_boolean(it['defaultTarget']) },
          "IMAGE TARGET" => lambda {|it| format_boolean(it['defaultStore']) }
        }
        print cyan
        print as_pretty_table(rows, tenant_columns)
      end

      print reset,"\n"
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def update(args)
    options = {}
    datastore_id = nil
    cloud_id = nil
    tenants = nil
    group_access_all = nil
    group_access_list = nil
    group_defaults_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[datastore] [options]")
      opts.add_hidden_option('-c') # prefer args[0] for [cloud]
      opts.on('--group-access-all [on|off]', String, "Toggle Access for all groups.") do |val|
        group_access_all = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      opts.on('--group-access LIST', Array, "Group Access, comma separated list of group IDs.") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          group_access_list = []
        else
          group_access_list = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--tenants LIST', Array, "Tenant Access, comma separated list of account IDs") do |list|
        if list.size == 1 && list[0] == 'null' # hacky way to clear it
          options['tenants'] = []
        else
          options['tenants'] = list.collect {|it| it.to_s.strip.empty? ? nil : it.to_s.strip }.compact.uniq
        end
      end
      opts.on('--visibility [private|public]', String, "Visibility") do |val|
        options['visibility'] = val
      end
      opts.on('--active [on|off]', String, "Can be used to disable a datastore") do |val|
        options['active'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s == ''
      end
      build_common_options(opts, options, [:options, :payload, :json, :dry_run, :remote])
      opts.footer = "Update a datastore." + "\n" +
                    "[cloud] is required. This is the name or id of the cloud." + "\n" +
                    "[datastore] is required. This is the name or id of a datastore."
    end
    optparse.parse!(args)
    if args.count == 1
      datastore_id = args[0]
    else
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    connect(options)

    begin
      datastore = find_datastore_by_name_or_id(datastore_id)
      return 1 if datastore.nil?
      
      # merge -O options into normally parsed options
      options.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      # construct payload
      payload = nil
      if options[:payload]
        payload = options[:payload]
      else
        # prompt for datastore options
        payload = {
          'datastore' => {
          }
        }
        
        # allow arbitrary -O options
        payload['datastore'].deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

      
        # Group Access
        if group_access_all != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['all'] = group_access_all
        end
        if group_access_list != nil
          payload['resourcePermissions'] ||= {}
          payload['resourcePermissions']['sites'] = group_access_list.collect do |site_id|
            site = {"id" => site_id.to_i}
            if group_defaults_list && group_defaults_list.include?(site_id)
              site["default"] = true
            end
            site
          end
        end

        # Tenants
        if options['tenants']
          payload['tenantPermissions'] = {}
          payload['tenantPermissions']['accounts'] = options['tenants']
        end

        # Active
        if options['active'] != nil
          payload['datastore']['active'] = options['active']
        end
        
        # Visibility
        if options['visibility'] != nil
          payload['datastore']['visibility'] = options['visibility']
        end

        if payload['datastore'].empty? && payload['resourcePermissions'].nil? && payload['tenantPermissions'].nil?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

      end
      @storage_datastore_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @storage_datastore_interface.dry.update(datastore["id"], payload)
        return
      end
      json_response = @storage_datastore_interface.update(datastore["id"], payload)
      if options[:json]
        puts as_json(json_response)
      else
        datastore = json_response['data']['datastore']
        print_green_success "Updated datastore #{datastore['name']}"
        get([datastore['id']])
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      return 1
    end
  end

  def load_option_types_for_datastore_type(datastore_type)
    return @storage_datastore_interface.load_type_options(datastore_type)
  end

  def find_datastore_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_datastore_by_id(val)
    else
      return find_datastore_by_name(val)
    end
  end

  def find_datastore_by_id(id)
    begin
      json_response = @storage_datastore_interface.get(id.to_i)
      return json_response['datastore']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Datastore not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_datastore_by_name(name)
    json_response = @storage_datastore_interface.list({name: name.to_s})
    datastores = json_response['datastores']
    if datastores.empty?
      print_red_alert "Datastore not found by name #{name}"
      return nil
    elsif datastores.size > 1
      print_red_alert "#{datastores.size} datastores found by name #{name}"
      rows = datastores.collect do |it|
        {id: it['id'], name: it['name']}
      end
      print "\n"
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      datastore = datastores[0]
      # merge in tenants map
      if json_response['tenants'] && json_response['tenants'][datastore['id']]
        datastore['tenants'] = json_response['tenants'][datastore['id']]
      end
      return datastore
    end
  end

end