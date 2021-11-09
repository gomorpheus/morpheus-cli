# require 'yaml'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancers'
  register_subcommands :list, :get, :add, :update, :remove

  # deprecated the `load-balancers types` command in 5.3.2, it moved to `load-balancer-types list`
  register_subcommands :types
  set_subcommands_hidden :types

  # RestCommand settings
  register_interfaces :load_balancers, :load_balancer_types
  set_rest_has_type true
  # set_rest_type :load_balancer_types

  def render_response_for_get(json_response, options)
    render_response(json_response, options, rest_object_key) do
      record = json_response[rest_object_key]
      print_h1 rest_label, [], options
      print cyan
      print_description_list(rest_column_definitions, record, options)
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

  # deprecated, to be removed in the future.
  def types(args)
    print_error yellow,"[DEPRECATED] The command `load-balancers types` is deprecated and replaced by `load-balancer-types list`.",reset,"\n"
    my_terminal.execute("load-balancer-types list #{args.join(' ')}")
  end

  protected

  def load_balancer_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Type" => lambda {|it| it['type'] ? it['type']['name'] : '' },
      "Cloud" => lambda {|it| it['cloud'] ? it['cloud']['name'] : '' },
      "Host" => lambda {|it| it['host'] }
    }
  end

  def load_balancer_column_definitions()
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
  def find_load_balancer_type_by_name_or_id(name)
    load_balancer_type_for_name_or_id(name)
  end



end
