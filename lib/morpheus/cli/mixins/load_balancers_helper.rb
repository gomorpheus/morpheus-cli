require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for load balancer management
# including load balancers, load balancer types, virtual servers, etc.
module Morpheus::Cli::LoadBalancersHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def load_balancers_interface
    # @api_client.load_balancers
    raise "#{self.class} has not defined @load_balancers_interface" if @load_balancers_interface.nil?
    @load_balancers_interface
  end

  def load_balancer_types_interface
    # @api_client.load_balancer_types
    raise "#{self.class} has not defined @load_balancer_types_interface" if @load_balancer_types_interface.nil?
    @load_balancer_types_interface
  end

  def load_balancer_object_key
    'loadBalancer'
  end

  def load_balancer_list_key
    'loadBalancers'
  end

  def load_balancer_label
    'Load Balancer'
  end

  def load_balancer_plural_label
    'Load Balancers'
  end

  def load_balancer_type_object_key
    'loadBalancerType'
  end

  def load_balancer_type_list_key
    'loadBalancerTypes'
  end

  def load_balancer_type_label
    'Load Balancer Type'
  end

  def load_balancer_type_plural_label
    'Load Balancer Types'
  end

  def find_lb_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_lb_by_id(val)
    else
      return find_lb_by_name(val)
    end
  end

  def find_lb_by_id(id)
    begin
      json_response = load_balancers_interface.get(id.to_i)
      return json_response[load_balancer_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Load Balancer not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_lb_by_name(name)
    lbs = load_balancers_interface.list({name: name.to_s})[load_balancer_list_key]
    if lbs.empty?
      print_red_alert "Load Balancer not found by name #{name}"
      return nil
    elsif lbs.size > 1
      print_red_alert "#{lbs.size} load balancers found by name #{name}"
      #print_lbs_table(lbs, {color: red})
      print reset,"\n\n"
      return nil
    else
      return lbs[0]
    end
  end

  def get_available_load_balancer_types(refresh=false)
    if !@available_load_balancer_types || refresh
      @available_load_balancer_types = load_balancer_types_interface.list({max:1000})[load_balancer_type_list_key]
    end
    return @available_load_balancer_types
  end

  def load_balancer_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return load_balancer_type_for_id(val)
    else
      return load_balancer_type_for_name(val)
    end
  end

  def load_balancer_type_for_id(id)
    return get_available_load_balancer_types().find { |z| z['id'].to_i == id.to_i}
  end

  def load_balancer_type_for_name(name)
    return get_available_load_balancer_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  def find_load_balancer_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_load_balancer_type_by_id(val)
    else
      return find_load_balancer_type_by_name(val)
    end
  end

  def find_load_balancer_type_by_id(id)
    begin
      json_response = load_balancer_types_interface.get(id.to_i)
      return json_response[load_balancer_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Load Balancer Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_load_balancer_type_by_name(name)
    json_response = load_balancer_types_interface.list({name: name.to_s})
    load_balancer_types = json_response[load_balancer_type_list_key]
    if load_balancer_types.empty?
      print_red_alert "Load Balancer Type not found by name #{name}"
      return load_balancer_types
    elsif load_balancer_types.size > 1
      print_red_alert "#{load_balancer_types.size} load balancer types found by name #{name}"
      rows = load_balancer_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return load_balancer_types[0]
    end
  end

end
