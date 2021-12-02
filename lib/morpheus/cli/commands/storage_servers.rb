require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageServers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageServersHelper

  set_command_name :'storage-servers'
  set_command_description "View and manage storage servers."
  register_subcommands :list, :get, :add, :update, :remove

  # RestCommand settings
  register_interfaces :storage_servers, :storage_server_types
  set_rest_has_type true
  # set_rest_type :storage_server_types

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # show Storage Server Configuration
      config = record['config']
      if config && !config.empty?
        print_h2 "Configuration"
        print_description_list(config.keys, config)
      end
      print reset,"\n"
    end
  end

  protected

  def storage_server_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Service URL" => lambda {|it| it['serviceUrl'] },
      "Tenants" => lambda {|it| 
        if it['tenants'] && !it['tenants'].empty?
          it['tenants'].collect {|account| account['name'] }.join(', ')
        else
          it['owner'] ? it['owner']['name'] : (it['account'] ? it['account']['name'] : nil)
        end
      },
    }
  end

  def storage_server_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Service URL" => lambda {|it| it['serviceUrl'] },
      "Service Username" => lambda {|it| it['serviceUsername'] },
      "Tenants" => lambda {|it| it['tenants'].collect {|account| account['name'] }.join(', ') },
      "Owner" => lambda {|it| it['owner'] ? it['owner']['name'] : (it['account'] ? it['account']['name'] : nil) },
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Status" => lambda {|it| format_storage_server_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  # overridden to work with name or code
  def find_storage_server_type_by_name_or_id(name)
    storage_server_type_for_name_or_id(name)
  end

  def add_storage_server_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
#      {'fieldName' => 'type', 'fieldLabel' => 'Storage Server Type', 'type' => 'select', 'optionSource' => 'storageServerTypes', 'required' => true},
    ]
  end

  def add_storage_server_advanced_option_types()
    [
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'fieldGroup' => 'Advanced', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions'},
      {'fieldName' => 'tenants', 'fieldLabel' => 'Tenants', 'fieldGroup' => 'Advanced', 'type' => 'multiSelect', 'optionSource' => lambda { |api_client, api_params| 
        api_client.options.options_for_source("allTenants", {})['data']
      }},
    ]
  end

  def update_storage_server_option_types()
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
      {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox'},
    ]
  end

  def update_storage_server_advanced_option_types()
    add_storage_server_advanced_option_types()
  end

  def format_storage_server_status(storage_server, return_color=cyan)
    out = ""
    status_string = storage_server['status']
    if storage_server['enabled'] == false
      out << "#{red}DISABLED#{return_color}"
    elsif status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{storage_server['statusMessage'] ? "#{return_color} - #{storage_server['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

end
