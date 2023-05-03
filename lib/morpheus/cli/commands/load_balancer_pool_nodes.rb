require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerPoolNodes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_description "View and manage load balancer pool member nodes."
  set_command_name :'load-balancer-pool-nodes'

  set_rest_key :load_balancer_node
  set_rest_parent_name :load_balancer_pools
  set_rest_option_context_map({'loadBalancerNode' => ''})

  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :load_balancer_types, :load_balancer_pools

  protected

  def load_balancer_node_list_column_definitions(options)
    {
      "ID" => 'id',
      "Status" => 'status',
      "Name" => 'name',
      "IP Address" => 'ipAddress',
      "Port" => 'port'
    }
  end

  def load_balancer_node_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "State" => lambda {|it| it['config']['adminState']},
      "IP Address" => 'ipAddress',
      "Port" => 'port',
      "Weight" => 'weight',
      "Backup Member" => lambda {|it| format_boolean it['config']['backupMember']},
      "Max Concurrent Connections" => lambda {|it| it['config']['maxConcurrentConnections']}
    }
  end

  def load_balancer_node_object_key
    'loadBalancerNode'
  end

  def load_balancer_node_list_key
    'loadBalancerNodes'
  end

  def load_balancer_node_label
    'Load Balancer Node'
  end

  def load_balancer_node_label_plural
    'Load Balancer Nodes'
  end

  def format_load_balancer_pool_status(record, return_color=cyan)
    out = ""
    status_string = record['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'warning'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{record['statusMessage'] ? "#{return_color} - #{record['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def load_option_types_for_load_balancer_node(type_record, parent_record)
    load_balancer_pool = parent_record
    load_balancer_type = find_by_id(:load_balancer_type, load_balancer_pool['loadBalancer']['type']['id'])
    load_balancer_type['nodeOptionTypes']
  end

  def find_load_balancer_node_by_name_or_id(parent_id, val)
    (@load_balancer_pool_nodes_interface.get(parent_id, val)['loadBalancerNode']) rescue nil
  end
  ## using CliCommand's generic find_by methods

end
