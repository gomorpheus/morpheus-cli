require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerPools
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_description "View and manage load balancer pools."
  set_command_name :'load-balancer-pools'

  set_rest_interface_name :load_balancer_pools_secondary
  set_rest_parent_name :load_balancers

  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :load_balancer_pools_secondary, :load_balancers, :load_balancer_types


  # set_rest_interface_name :load_balancer_pools
  # set_parent_rest_interface_name :load_balancers
  
  # todo: a configurable way to load the optionTypes
  # option_types = loadBalancer['poolOptionTypes']
  # set_rest_has_type true
  # set_rest_type :load_balancer_virtual_server_types

  protected

  def load_balancer_pool_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      #"Load Balancer" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Balancer Mode" => lambda {|it| it['vipBalance'] },
      "Status" => lambda {|it| format_load_balancer_pool_status(it) }
    }
  end

  def load_balancer_pool_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Load Balancer" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Description" => 'description',
      "Balancer Mode" => lambda {|it| it['vipBalance'] },
      # todo: more properties to show here
      "Status" => lambda {|it| format_load_balancer_pool_status(it) },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def load_balancer_pool_object_key
    'loadBalancerPool'
  end

  def load_balancer_pool_list_key
    'loadBalancerPools'
  end

  def load_balancer_pool_label
    'Load Balancer Pool'
  end

  def load_balancer_pool_label_plural
    'Load Balancer Pools'
  end

  def format_load_balancer_pool_status(record, return_color=cyan)
    out = ""
    status_string = record['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'online' || status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{record['statusMessage'] ? "#{return_color} - #{record['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def load_option_types_for_load_balancer_pool(type_record, parent_record)
    load_balancer = parent_record
    load_balancer_type_id = load_balancer['type']['id']
    load_balancer_type = find_by_id(:load_balancer_type, load_balancer_type_id)
    load_balancer_type['poolOptionTypes']
  end

  ## using CliCommand's generic find_by methods

  def find_load_balancer_pool_by_name_or_id(load_balancer_pool_id, val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_load_balancer_pool_by_id(load_balancer_pool_id, val)
    else
      return find_load_balancer_pool_by_name(load_balancer_pool_id, val)
    end
  end

  def find_load_balancer_pool_by_id(load_balancer_pool_id, id)
    begin
      json_response = @load_balancer_pools_secondary_interface.get(load_balancer_pool_id, id.to_i)
      return json_response[load_balancer_pool_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Load Balancer Pool not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_load_balancer_pool_by_name(load_balancer_pool_id, name)
    lbs = @load_balancer_pools_secondary_interface.list(load_balancer_pool_id, {name: name.to_s})[load_balancer_pool_list_key]
    if lbs.empty?
      print_red_alert "Load Balancer Pool not found by name #{name}"
      return nil
    elsif lbs.size > 1
      print_red_alert "#{lbs.size} load balancer pools found by name #{name}"
      #print_lbs_table(lbs, {color: red})
      print reset,"\n\n"
      return nil
    else
      return lbs[0]
    end
  end

end
