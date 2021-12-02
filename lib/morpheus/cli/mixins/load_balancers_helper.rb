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

  def load_balancer_label_plural
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

  def load_balancer_type_label_plural
    'Load Balancer Types'
  end

  def find_load_balancer_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_load_balancer_by_id(val)
    else
      return find_load_balancer_by_name(val)
    end
  end

  def find_load_balancer_by_id(id)
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

  def find_load_balancer_by_name(name)
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

  def load_balancer_type_for_id(val)
    record = get_available_load_balancer_types().find { |z| z['id'].to_i == val.to_i}
    label = "Load Balancer Type"
    if record.nil?
      print_red_alert "#{label.downcase} not found by id #{val}"
      return nil
    end
    return record
  end

  def load_balancer_type_for_name(val)
    records = get_available_load_balancer_types().select { |z| z['name'].downcase == val.downcase || z['code'].downcase == val.downcase}
    label = "Load Balancer Type"
    if records.empty?
      print_red_alert "#{label} not found by name '#{val}'"
      return nil
    elsif records.size > 1
      print_red_alert "More than one #{label.downcase} found by name '#{val}'"
      print_error "\n"
      puts_error as_pretty_table(records, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return records[0]
    end
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
