require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerMonitors
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_description "View and manage load balancer monitors."
  set_command_name :'load-balancer-monitors'
  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :load_balancer_monitors,
                      :load_balancers, :load_balancer_types

  set_rest_parent_name :load_balancers

  # set_rest_interface_name :load_balancer_monitors
  # set_parent_rest_interface_name :load_balancers
  
  # todo: a configurable way to load the optionTypes
  # option_types = loadBalancer['monitorOptionTypes']
  # set_rest_has_type true
  # set_rest_type :load_balancer_virtual_server_types

  protected

  def load_balancer_monitor_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Monitor Type" => lambda {|it| it['monitorTypeDisplay'] || it['monitorType'] },
    }
  end

  def load_balancer_monitor_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Load Balancer" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Description" => 'description',
      "Monitor Type" => lambda {|it| it['monitorTypeDisplay'] || it['monitorType'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def load_balancer_monitor_object_key
    'loadBalancerMonitor'
  end

  def load_balancer_monitor_list_key
    'loadBalancerMonitors'
  end

  def load_balancer_monitor_label
    'Load Balancer Monitor'
  end

  def load_balancer_monitor_label_plural
    'Load Balancer Monitors'
  end

  def load_option_types_for_load_balancer_monitor(type_record, parent_record)
    load_balancer = parent_record
    load_balancer_type_id = load_balancer['type']['id']
    load_balancer_type = find_by_id(:load_balancer_type, load_balancer_type_id)
    load_balancer_type['monitorOptionTypes']
  end

end
