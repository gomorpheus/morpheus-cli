require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkServersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_description "View and manage network servers"
  set_command_name :'network-servers'

  register_subcommands :list, :get, :add, :update, :remove, :refresh
  register_subcommands :list_types, :get_type
  alias_subcommand :types, :'list-types'
  alias_subcommand :type, :'get-type'
  
  # RestCommand settings
  register_interfaces :network_servers, :network_server_types, :clouds, :options
  set_rest_has_type true
  set_rest_type :network_server_types

  def handle(args)
    handle_subcommand(args)
  end

  def add(args)
    options = {params: {}}
    params = options[:params]
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name for this network server") do |val|
        params['name'] = val
      end
      opts.on('--type VALUE', String, "Network Server Type code") do |val|
        params['type'] = val
      end
      # opts.on('--enabled [on|off]', String, "Can be used to disable the network server") do |val|
      #   params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      # end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
      #build_option_type_options(opts, options, add_network_server_option_types)
      build_option_type_options(opts, options, add_network_server_advanced_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new network server.
[name] is required and can be passed as --name instead.
Configuration options vary by network server type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, max: 1)
    connect(options)

    # support [name] as first argument
    if args[0]
      params['name'] = args[0]
    end

    # merge -O options into normally parsed options
    #params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # construct payload
    payload = nil
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => parse_passed_options(options)})
      payload.deep_merge!({rest_object_key => params})
    else
      payload = {}
      payload.deep_merge!({rest_object_key => parse_passed_options(options)})
      # Name
      if !params['name']
        params['name'] = prompt_value({'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network server.'}, options)
        # params['name'] = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network server.'}], params, @api_client, {}, options[:no_prompt])['name']
      end

      # Network Server Type
      network_type_id = nil
      # use this optionSource networkServices which is really network service 
      # where the response data is categories, each with a list ofservices (service types)
      network_services_options = @options_interface.options_for_source('networkServices',{})['data']
      networking_category = network_services_options.find {|it| it['value'] == 'networkServer'}
      service_types = networking_category ? networking_category['services'] : []
      network_server_type_options = service_types.collect {|it| {'name' => it['name'], 'value' => it['code'], 'code' => it['code'], 'id' => it['id']} }
      if network_server_type_options.empty?
        raise_command_error "No available network server types found"
      end
      # v_prompt = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Network Server Type', 'type' => 'select', 'optionSource' => 'networkServerTypes', 'required' => true, 'description' => 'Choose a network server type.'}], options, @api_client, {})
      #network_type_id = v_prompt['type']
      # allow matching type by id, name or code
      selected_type = nil
      if params['type'] && params['type'].to_s =~ /\A\d{1,}\Z/
        network_type_id = params['type'].to_i
        selected_type = network_server_type_options.find {|it| it['id'] == network_type_id }
        if selected_type.nil?
          raise_command_error "Network Server Type not found by id '#{params['type']}'"
        end
        network_type_code = selected_type['code']
      else
        network_type_code = prompt_value({'fieldName' => 'type', 'fieldLabel' => 'Network Server Type', 'type' => 'select', 'selectOptions' => network_server_type_options, 'required' => true, 'description' => 'Choose a network server type.'}, options.merge(params))
        #network_type_code = Morpheus::Cli::OptionTypes.prompt([{'fieldName' => 'type', 'fieldLabel' => 'Network Server Type', 'type' => 'select', 'selectOptions' => network_server_type_options, 'required' => true, 'description' => 'Choose a network server type.'}], options, @api_client, {}, options[:no_prompt])['type']
        selected_type = network_server_type_options.find {|it| it['code'] == network_type_code }
        if selected_type.nil?
          raise_command_error "Network Server Type not found by name or code '#{params['type']}'"
        end
        network_type_id = selected_type['id']
      end
      params['type'] = network_type_code
      
      # prompt options by type
      network_server_type = @network_server_types_interface.get(network_type_id.to_i)['networkServerType']
      # params['type'] = network_server_type['code']
      type_options_types = network_server_type['optionTypes'] || []
      type_options_types.reject! {|it| it['fieldName'] == 'visibility' } # skip visibility, its under advanced now
      option_result = prompt(network_server_type['optionTypes'], options.merge({:context_map => {'networkServer' => ''}}))
      params.deep_merge!(option_result)

      # advanced options
      advanced_option_types = add_network_server_advanced_option_types
      if advanced_option_types && !advanced_option_types.empty?
        v_prompt = Morpheus::Cli::OptionTypes.prompt(advanced_option_types, options[:options], @api_client, {})
        v_prompt.deep_compact!
        v_prompt.booleanize! # 'on' => true
        params.deep_merge!(v_prompt)
      end
      payload.deep_merge!({rest_object_key => params})
    end
    @network_servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.create(payload)
      return
    end
    json_response = @network_servers_interface.create(payload)
    render_response(json_response, options, 'networkServer') do
      network_server = json_response['networkServer']
      print_green_success "Added network server #{network_server['name']}"
      _get(network_server['id'], {}, options)
    end
  end

  def update(args)
    options = {}
    params = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network server] [options]")
      opts.on('--name VALUE', String, "Name for this network server") do |val|
        params['name'] = val
      end
      # opts.on('--enabled [on|off]', String, "Can be used to enable or disable the network server") do |val|
      #   params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      # end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
      #build_option_type_options(opts, options, update_network_server_option_types)
      build_option_type_options(opts, options, update_network_server_advanced_option_types)
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a network server.
[network server] is required. This is the name or id of a network server.
Configuration options vary by network server type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 1)
    connect(options)
    # find network server to be updated
    network_server = find_network_server_by_name_or_id(args[0])
    return 1 if network_server.nil?
    
    # merge -O options into normally parsed options
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # params['tenants'] = options['tenants'].collect {|it| {'id': it}}
    # advanced options
    advanced_option_types = update_network_server_advanced_option_types
    if advanced_option_types && !advanced_option_types.empty?
      v_prompt = Morpheus::Cli::OptionTypes.no_prompt(advanced_option_types, options[:options], @api_client, {})
      v_prompt.deep_compact!
      v_prompt.booleanize! # 'on' => true
      params.deep_merge!(v_prompt)
    end

    # construct payload
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      payload = {
        'networkServer' => params
      }
    end
    @network_servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.update(network_server["id"], payload)
      return
    end
    json_response = @network_servers_interface.update(network_server["id"], payload)
    render_response(json_response, options, 'networkServer') do
      network_server = json_response['networkServer']
      print_green_success "Updated network server #{network_server['name']}"
      _get(network_server['id'], {}, options)
    end
  end

  def refresh(args)
    options = {}
    params = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[network server]")
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
            build_standard_update_options(opts, options, [:query])
      opts.footer = <<-EOT
Refresh a network server.
[network server] is required. This is the name or id of a network server.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count: 1)
    connect(options)
    # find network server to be updated
    network_server = find_network_server_by_name_or_id(args[0])
    return 1 if network_server.nil?
    # construct query parameters
    params.merge!(parse_query_options(options))
    # construct payload
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      payload = options[:options].reject {|k,v| k.is_a?(Symbol) }
    end
    @network_servers_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @network_servers_interface.dry.refresh(network_server["id"], params, payload)
      return
    end
    json_response = @network_servers_interface.refresh(network_server["id"], params, payload)
    render_response(json_response, options, 'networkServer') do
      #network_server = json_response['networkServer']
      print_green_success "Refreshing network server #{network_server['name']}"
      #_get(network_server['id'], {}, options)
    end
  end

  private

  def network_server_list_key
    'networkServers'
  end

  def network_server_object_key
    'networkServer'
  end

  def render_response_for_get(json_response, options)
    record = json_response[rest_object_key]
    options[:exclude_tenants] = record['tenants'].nil?
    super(json_response, options)
  end

  def find_network_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_network_server_by_id(val)
    else
      return find_network_server_by_name(val)
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
    json_response = @network_servers_interface.list({name: name.to_s})
    network_servers = json_response['networkServers']
    if network_servers.empty?
      print_red_alert "Network Server not found by name #{name}"
      return nil
    elsif network_servers.size > 1
      print_red_alert "#{network_servers.size} network servers found by name #{name}"
      # print_networks_table(networks, {color: red})
      rows = network_servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return network_servers[0]
    end
  end

  def add_network_server_option_types()
    [
      {'shorthand' => '-t', 'fieldName' => 'type', 'fieldLabel' => 'Network Server Type', 'type' => 'select', 'optionSource' => lambda {|api_client, api_params| 
        api_client.network_server_types.list({max:10000})['networkServerTypes'].collect { |it| {"name" => it["name"], "value" => it["code"]} }
      }, 'required' => true},
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
    ]
  end

  def add_network_server_advanced_option_types()
    [
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'private'},
      {'fieldName' => 'tenants', 'fieldLabel' => 'Tenants', 'fieldGroup' => 'Advanced', 'type' => 'multiSelect', 'resultValueField' => 'id', 'optionSource' => lambda { |api_client, api_params|
        api_client.options.options_for_source("allTenants", {})['data']
      }},
    ]
  end

  def update_network_server_option_types()
    list = add_network_server_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list = list.reject {|it| ["type"].include? it['fieldName'] }
    list
  end

  def update_network_server_advanced_option_types()
    list = add_network_server_advanced_option_types.collect {|it|
      it.delete('required')
      it.delete('defaultValue')
      it
    }
    list
  end

  def network_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      # "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_network_server_status(it) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def network_server_column_definitions(options)
    columns = {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "Credentials" => lambda {|it| it['credential'] ? (it['credential']['type'] == 'local' ? '(Local)' : it['credential']['name']) : nil },
      "Username" => lambda {|it| it['serviceUsername'] },
      "Password" => lambda {|it| it['servicePassword'] },
      "Service Mode" => lambda {|it| it['serviceMode'] },
      "Service Path" => lambda {|it| it['servicePath'] },
      "Network Filter" => lambda {|it| it['networkFilter'] },
      "Tenant Match" => lambda {|it| it['tenantMatch'] },
      #"Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Visibility" => lambda {|it| it['visibility'] ? it['visibility'].capitalize() : '' },
      "Tenants" => lambda { |it| it['tenants'].collect {|tenant| tenant['name']}.join(', ') rescue '' },
      "Status" => lambda {|it| format_network_server_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
    if options[:exclude_tenants]
      columns.delete("Tenants")
    end
    columns
  end

  def format_network_server_status(network_server, return_color=cyan)
    out = ""
    status_string = network_server['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{network_server['statusMessage'] ? "#{return_color} - #{network_server['statusMessage']}" : ''}#{return_color}"
    # elsif network_server['enabled'] == false
    #   out << "#{red}DISABLED#{network_server['statusMessage'] ? "#{return_color} - #{network_server['statusMessage']}" : ''}#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'error' || status_string == 'offline'
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{network_server['statusMessage'] ? "#{return_color} - #{network_server['statusMessage']}" : ''}#{return_color}"
    else
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    end
    out
  end

end
