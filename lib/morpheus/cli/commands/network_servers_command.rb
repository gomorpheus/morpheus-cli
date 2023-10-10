require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkServersCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_description "View and manage network servers"
  set_command_name :'network-servers'

  register_subcommands :list, :get, :add, :update, :remove
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
    options = {}
    params = {}
    ip_range_list = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--name VALUE', String, "Name for this network server") do |val|
        params['name'] = val
      end
      opts.on('--type VALUE', String, "Network Server Type code") do |val|
        params['type'] = val
      end
      opts.on('--enabled [on|off]', String, "Can be used to disable the network server") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
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
    params.deep_merge!(options[:options].reject {|k,v| k.is_a?(Symbol) }) if options[:options]

    # construct payload
    payload = nil
    if options[:payload]
      payload = options[:payload]
    else
      # prompt for network server options
      
      # Name
      if !params['name']
        params['name'] = prompt_value({'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'description' => 'Name for this network server.'}, params, options[:no_prompt])
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
        network_type_code = prompt_value({'fieldName' => 'type', 'fieldLabel' => 'Network Server Type', 'type' => 'select', 'selectOptions' => network_server_type_options, 'required' => true, 'description' => 'Choose a network server type.'}, params, options[:no_prompt])
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
      option_result = Morpheus::Cli::OptionTypes.prompt(network_server_type['optionTypes'], params.merge({:context_map => {'networkServer' => ''}}), @api_client, {}, options[:no_prompt], true)
      params.deep_merge!(option_result)
      payload = {'networkServer' => params}
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
      opts.on('--enabled [on|off]', String, "Can be used to enable or disable the network server") do |val|
        params['enabled'] = val.to_s == 'on' || val.to_s == 'true' || val.to_s.empty?
      end
      # ['name', 'serviceUsername', 'servicePassword', 'servicePort', 'serviceHost', 'serviceUrl', 'serviceMode', 'networkFilter', 'tenantMatch']
            build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Update a network server.
"[server] is required. This is the name or id of a network server."
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

  private

  # def render_response_for_get(json_response, options)
  #   # load the type and show fields dynamically based on optionTypes
  #   render_response(json_response, options, rest_object_key) do
  #     type_record = rest_type_find_by_name_or_id(json_response[rest_object_key]['type']['id']) rescue nil
  #     type_option_types = type_record ? (type_record['optionTypes'] || []) : []
  #     record = json_response[rest_object_key]
  #     print_h1 rest_label, [], options
  #     print cyan
  #     columns = rest_column_definitions(options)
  #     if record['credential'] && record['credential']['type'] != 'local'
  #       columns.delete("Username")
  #       columns.delete("Password")
  #     end
  #     columns.delete("Throttle Rate") unless type_option_types.find {|it| it['fieldName'] == 'serviceThrottleRate' }
  #     columns.delete("Disable SSL SNI") unless type_option_types.find {|it| it['fieldName'] == 'ignoreSsl' }
  #     columns.delete("Network Filter") unless type_option_types.find {|it| it['fieldName'] == 'networkFilter' }
  #     columns.delete("Zone Filter") unless type_option_types.find {|it| it['fieldName'] == 'zoneFilter' }
  #     columns.delete("Tenant Match") unless type_option_types.find {|it| it['fieldName'] == 'tenantMatch' }
  #     columns.delete("IP Mode") unless type_option_types.find {|it| it['fieldName'] == 'serviceMode' }
  #     columns.delete("Extra Attributes") unless type_option_types.find {|it| it['fieldName'] == 'extraAttributes' }
  #     columns.delete("App ID") unless type_option_types.find {|it| it['fieldName'] == 'appId' }
  #     columns.delete("Inventory Existing") unless type_option_types.find {|it| it['fieldName'] == 'inventoryExisting' }
  #     columns.delete("Enabled") if record['enabled'].nil? # was not always returned, so don't show false if not present..
  #     print_description_list(columns, record, options)
  #     print reset,"\n"
  #   end
  # end

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
    []
  end

  def update_network_server_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox'},
    ]
  end

  def update_network_server_advanced_option_types()
    []
  end

  def network_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_network_server_status(it) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
  end

  def network_server_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => lambda {|it| it['name'] },
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "URL" => lambda {|it| it['serviceUrl'] },
      #todo: support credentials
      #"Credentials" => lambda {|it| it['credential'] ? (it['credential']['type'] == 'local' ? '(Local)' : it['credential']['name']) : nil },
      "Username" => lambda {|it| it['serviceUsername'] },
      "Password" => lambda {|it| it['servicePassword'] },
      "Service Mode" => lambda {|it| it['serviceMode'] },
      "Service Path" => lambda {|it| it['servicePath'] },
      "Network Filter" => lambda {|it| it['networkFilter'] },
      "Tenant Match" => lambda {|it| it['tenantMatch'] },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_network_server_status(it) },
      "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Last Updated" => lambda {|it| format_local_dt(it['lastUpdated']) },
    }
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
