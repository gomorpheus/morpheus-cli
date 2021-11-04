require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerPools
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_hidden # hide until ready
  set_command_name :'load-balancer-pools'
  register_subcommands :list, :get, :add, :update, :remove

  register_interfaces :load_balancer_pools,
                      :load_balancers, :load_balancer_pools

  protected

  def load_balancer_pool_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Balancer Mode" => lambda {|it| it['vipBalance'] },
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
    }
  end

  def load_balancer_pool_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Balancer Mode" => lambda {|it| it['vipBalance'] },
      "LB" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
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

  def find_load_balancer_pool_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_load_balancer_pool_by_id(val)
    else
      return find_load_balancer_pool_by_name(val)
    end
  end

  def find_load_balancer_pool_by_id(id)
    begin
      json_response = load_balancer_pools_interface.get(id.to_i)
      return json_response[load_balancer_pool_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "#{load_balancer_pool_label} not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_load_balancer_pool_by_name(name)
    json_response = load_balancer_pools_interface.list({name: name.to_s})
    load_balancer_pools = json_response[load_balancer_pool_list_key]
    if load_balancer_pools.empty?
      print_red_alert "#{load_balancer_pool_label_plural} not found by name #{name}"
      return load_balancer_pools
    elsif load_balancer_pools.size > 1
      print_red_alert "#{load_balancer_pools.size} #{load_balancer_pool_label_plural.downcase} found by name #{name}"
      rows = load_balancer_pools.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return load_balancer_pools[0]
    end
  end

  def format_load_balancer_pool_status(pool, return_color=cyan)
    out = ""
    status_string = pool['vipStatus'] || pool['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'ok'
      out << "#{green}#{status_string.upcase}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.upcase}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.upcase : 'N/A'}#{pool['statusMessage'] ? "#{return_color} - #{pool['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

end
