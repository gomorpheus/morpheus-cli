require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerVirtualServers
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  # include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_hidden # hide until ready
  set_command_name :'load-balancer-virtual-servers'
  register_subcommands :list, :get, :add, :update, :remove

  register_interfaces :load_balancer_virtual_servers,
                      :load_balancers, :load_balancer_types

  # set_rest_parent_name :load_balancers

  # set_rest_interface_name :load_balancer_virtual_servers
  # set_parent_rest_interface_name :load_balancers
  
  # todo: a configurable way to load the optionTypes
  # option_types = loadBalancer['vipOptionTypes']
  # set_rest_has_type true
  # set_rest_type :load_balancer_virtual_server_types

  set_rest_arg 'vipName'

  protected

  def load_balancer_virtual_server_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'vipName',
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      # "Description" => 'description',
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : '(Unassigned)' },
      "Hostname" => lambda {|it| it['vipHostname'] },
      "VIP" => lambda {|it| it['vipAddress'] },
      "Protocol" => lambda {|it| it['vipProtocol'] },
      "Port" => lambda {|it| it['vipPort'] },
      "SSL" => lambda {|it| format_boolean(it['sslEnabled']) },
      "Status" => lambda {|it| format_virtual_server_status(it) },
    }
  end

  def load_balancer_virtual_server_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'vipName',
      "Description" => 'description',
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Instance" => lambda {|it| it['instance'] ? it['instance']['name'] : '(Unassigned)' },
      "Hostname" => lambda {|it| it['vipHostname'] },
      "VIP" => lambda {|it| it['vipAddress'] },
      "Protocol" => lambda {|it| it['vipProtocol'] },
      "Port" => lambda {|it| it['vipPort'] },
      "SSL" => lambda {|it| format_boolean(it['sslEnabled']) },
      # todo: more properties to show here
      "Status" => lambda {|it| format_virtual_server_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def load_balancer_virtual_server_object_key
    'virtualServer'
  end

  def load_balancer_virtual_server_list_key
    'virtualServers'
  end

  def load_balancer_virtual_server_label
    'Virtual Server'
  end

  def load_balancer_virtual_server_label_plural
    'Virtual Servers'
  end

  def find_load_balancer_virtual_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_load_balancer_virtual_server_by_id(val)
    else
      return find_load_balancer_virtual_server_by_name(val)
    end
  end

  def find_load_balancer_virtual_server_by_id(id)
    begin
      json_response = load_balancer_virtual_servers_interface.get(id.to_i)
      return json_response[load_balancer_virtual_server_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "#{load_balancer_virtual_server_label} not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_load_balancer_virtual_server_by_name(name)
    json_response = load_balancer_virtual_servers_interface.list({name: name.to_s})
    load_balancer_virtual_servers = json_response[load_balancer_virtual_server_list_key]
    if load_balancer_virtual_servers.empty?
      print_red_alert "#{load_balancer_virtual_server_label_plural} not found by name #{name}"
      return load_balancer_virtual_servers
    elsif load_balancer_virtual_servers.size > 1
      print_red_alert "#{load_balancer_virtual_servers.size} #{load_balancer_virtual_server_label_plural.downcase} found by name #{name}"
      rows = load_balancer_virtual_servers.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return load_balancer_virtual_servers[0]
    end
  end

  def format_virtual_server_status(virtual_server, return_color=cyan)
    out = ""
    status_string = virtual_server['vipStatus'] || virtual_server['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{virtual_server['statusMessage'] ? "#{return_color} - #{virtual_server['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

end
