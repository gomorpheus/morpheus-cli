require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper
  include Morpheus::Cli::ProvisioningHelper

  set_command_description "View and manage load balancers."
  set_command_name :'load-balancers'
  register_subcommands :list, :get, :add, :update, :remove, :refresh

  # deprecated the `load-balancers types` command in 5.3.2, it moved to `load-balancer-types list`
  register_subcommands :types
  set_subcommands_hidden :types

  # RestCommand settings
  register_interfaces :load_balancers, :load_balancer_types
  set_rest_has_type true
  # set_rest_type :load_balancer_types
  set_rest_perms_config({enabled:true, excludes:['plans', 'visibility']})

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions(options), record, options)
      # show LB Ports
      ports = record['ports']
      if ports && ports.size > 0
        print_h2 "LB Ports", options
        columns = [
          {"ID" => 'id'},
          {"Name" => 'name'},
          #{"Description" => 'description'},
          {"Port" => lambda {|it| it['port'] } },
          {"Protocol" => lambda {|it| it['proxyProtocol'] } },
          {"SSL" => lambda {|it| it['sslEnabled'] ? "Yes (#{it['sslCert'] ? it['sslCert']['name'] : 'none'})" : "No" } },
        ]
        print as_pretty_table(ports, columns, options)
      end
      print reset,"\n"
    end
  end

  def refresh(args)
    id = args[0]
    record_type = nil
    record_type_id = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[#{rest_arg}] [options]")
      build_standard_update_options(opts, options)
      opts.footer = <<-EOT
Refresh an existing #{rest_label.downcase}.
[#{rest_arg}] is required. This is the #{rest_has_name ? 'name or id' : 'id'} of #{a_or_an(rest_label)} #{rest_label.downcase}.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    record = rest_find_by_name_or_id(id)
    if record.nil?
      return 1, "#{rest_name} not found for '#{id}'"
    end
    passed_options = parse_passed_options(options)
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({rest_object_key => passed_options}) unless passed_options.empty?
    else
      record_payload = passed_options
      payload[rest_object_key] = record_payload
    end
    rest_interface.setopts(options)
    if options[:dry_run]
      print_dry_run rest_interface.dry.refresh(record['id'], payload)
      return
    end
    json_response = rest_interface.refresh(record['id'], payload)
    render_response(json_response, options, rest_object_key) do
      print_green_success "Refreshing #{rest_label.downcase} #{record['name'] || record['id']}"
      _get(record["id"], {}, options)
    end
    return 0, nil
  end

  # deprecated, to be removed in the future.
  def types(args)
    print_error yellow,"[DEPRECATED] The command `load-balancers types` is deprecated and replaced by `load-balancer-types list`.",reset,"\n"
    my_terminal.execute("load-balancer-types list #{args.join(' ')}")
  end

  protected

  # filtering for NSX-T only
  def rest_list_types()
    rest_type_interface.list({max:10000, creatable:true})[rest_type_list_key] # .reject {|it| it['code'] == 'nsx-t'}
  end

  def load_balancer_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Host" => lambda {|it| it['host'] }
    }
  end

  def load_balancer_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Visibility" => 'visibility',
      "IP" => 'ip',
      "Host" => 'host',
      "Port" => 'port',
      "Username" => 'username',
      # "SSL Enabled" => lambda {|it| format_boolean it['sslEnabled'] },
      # "SSL Cert" => lambda {|it| it['sslCert'] ? it['sslCert']['name'] : '' },
      # "SSL" => lambda {|it| it['sslEnabled'] ? "Yes (#{it['sslCert'] ? it['sslCert']['name'] : 'none'})" : "No" },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  # overridden to work with name or code
  # nope, api works with name=code now too
  # def find_load_balancer_type_by_name_or_id(name)
  #   load_balancer_type_for_name_or_id(name)
  # end

#   def add_load_balancer_option_types()
#     [
#       {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true},
#       {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text', 'required' => false},
#       {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'required' => false, 'defaultValue' => true},
# #      {'fieldName' => 'type', 'fieldLabel' => 'Storage Server Type', 'type' => 'select', 'optionSource' => 'loadBalancerTypes', 'required' => true},
#     ]
#   end

  def add_load_balancer_advanced_option_types()
    [
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'fieldGroup' => 'Advanced', 'type' => 'select', 'selectOptions' => [{'name' => 'Private', 'value' => 'private'},{'name' => 'Public', 'value' => 'public'}], 'required' => false, 'description' => 'Visibility', 'category' => 'permissions', 'defaultValue' => 'public'},
      {'fieldName' => 'tenants', 'fieldLabel' => 'Tenants', 'fieldGroup' => 'Advanced', 'type' => 'multiSelect', 'resultValueField' => 'id', 'optionSource' => lambda { |api_client, api_params|
        api_client.options.options_for_source("allTenants", {})['data']
      }},
    ]
  end

  # def update_load_balancer_option_types()
  #   [
  #     {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text'},
  #     {'fieldName' => 'description', 'fieldLabel' => 'Description', 'type' => 'text'},
  #     {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox'},
  #   ]
  # end

  def update_load_balancer_advanced_option_types()
    add_load_balancer_advanced_option_types()
  end

  def load_option_types_for_load_balancer(type_record, parent_record)
    load_balancer_type = type_record
    # reload it by id to get optionTypes
    option_types = load_balancer_type['optionTypes']
    if option_types.nil?
      load_balancer_type = find_by_id(:load_balancer_type, load_balancer_type['id'])
      if load_balancer_type.nil?
        raise_command_error("Load balancer type not found for id '#{id}'")
      end
      option_types = load_balancer_type['optionTypes']
    end
    return option_types
  end

end
