require 'morpheus/cli/mixins/print_helper'
# Provides common finder methods for VDI Pool management commands
module Morpheus::Cli::VdiHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  ## VDI Pools

  def vdi_pools_interface
    raise "#{self.class} has not defined @vdi_pools_interface" if @vdi_pools_interface.nil?
    @vdi_pools_interface
  end

  def vdi_pool_object_key
    'vdiPool'
  end

  def vdi_pool_list_key
    'vdiPools'
  end

  def find_vdi_pool_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_vdi_pool_by_id(val)
    else
      return find_vdi_pool_by_name(val)
    end
  end

  def find_vdi_pool_by_id(id)
    begin
      json_response = vdi_pools_interface.get(id.to_i)
      return json_response[vdi_pool_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "VDI Pool not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_vdi_pool_by_name(name)
    json_response = vdi_pools_interface.list({name: name.to_s})
    vdi_pools = json_response[vdi_pool_list_key]
    if vdi_pools.empty?
      print_red_alert "VDI Pool not found by name '#{name}'"
      return nil
    elsif vdi_pools.size > 1
      print_red_alert "#{vdi_pools.size} VDI Pools found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(vdi_pools, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return vdi_pools[0]
    end
  end

  def format_vdi_pool_status(vdi_pool, return_color=cyan)
    out = ""
    status_string = vdi_pool['status'].to_s.downcase
    if status_string
      if ['available'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      elsif ['unavailable'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{return_color}#{status_string.upcase}"
      end
    end
    out + return_color
  end

  ## VDI Allocations

  def vdi_allocations_interface
    raise "#{self.class} has not defined @vdi_allocations_interface" if @vdi_allocations_interface.nil?
    @vdi_allocations_interface
  end

  def vdi_allocation_object_key
    'vdiAllocation'
  end

  def vdi_allocation_list_key
    'vdiAllocations'
  end

  def find_vdi_allocation_by_id(id)
    begin
      json_response = vdi_allocations_interface.get(id.to_i)
      return json_response[vdi_allocation_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "VDI Allocation not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def format_vdi_allocation_status(vdi_allocation, return_color=cyan)
    out = ""
    status_string = vdi_allocation['status'].to_s.downcase
    if status_string
      if ['available'].include?(status_string)
        out << "#{green}#{status_string.upcase}"
      # elsif ['preparing'].include?(status_string)
      #   out << "#{yellow}#{status_string.upcase}"
      # elsif ['reserved', 'shutdown'].include?(status_string)
      #   out << "#{yellow}#{status_string.upcase}"
      elsif ['failed'].include?(status_string)
        out << "#{red}#{status_string.upcase}"
      else
        out << "#{return_color}#{status_string.upcase}"
      end
    end
    out + return_color
  end

  def get_available_vdi_apps(refresh=false)
    if !@available_vdi_apps || refresh
      @available_vdi_apps = @vdi_apps_interface.list({max:-1})['vdiApps'] #  || []
    end
    return @available_vdi_apps
  end
  
  def get_vdi_app_by_name_or_code(name)
    return get_available_vdi_apps().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  ## VDI Apps

  def vdi_apps_interface
    raise "#{self.class} has not defined @vdi_apps_interface" if @vdi_apps_interface.nil?
    @vdi_apps_interface
  end

  def vdi_app_object_key
    'vdiApp'
  end

  def vdi_app_list_key
    'vdiApps'
  end

  def find_vdi_app_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_vdi_app_by_id(val)
    else
      return find_vdi_app_by_name(val)
    end
  end

  def find_vdi_app_by_id(id)
    begin
      json_response = vdi_apps_interface.get(id.to_i)
      return json_response[vdi_app_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "VDI App not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_vdi_app_by_name(name)
    json_response = vdi_apps_interface.list({name: name.to_s})
    vdi_apps = json_response[vdi_app_list_key]
    if vdi_apps.empty?
      print_red_alert "VDI App not found by name '#{name}'"
      return nil
    elsif vdi_apps.size > 1
      print_red_alert "#{vdi_apps.size} VDI App found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(vdi_apps, {"ID" => 'id', "NAME" => 'name'}, {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return vdi_apps[0]
    end
  end


  ## VDI Gateways

  def vdi_gateways_interface
    raise "#{self.class} has not defined @vdi_gateways_interface" if @vdi_gateways_interface.nil?
    @vdi_gateways_interface
  end

  def vdi_gateway_object_key
    'vdiGateway'
  end

  def vdi_gateway_list_key
    'vdiGateways'
  end

  def find_vdi_gateway_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_vdi_gateway_by_id(val)
    else
      return find_vdi_gateway_by_name(val)
    end
  end

  def find_vdi_gateway_by_id(id)
    begin
      json_response = vdi_gateways_interface.get(id.to_i)
      return json_response[vdi_gateway_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "VDI Gateway not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_vdi_gateway_by_name(name)
    json_response = vdi_gateways_interface.list({name: name.to_s})
    vdi_gateways = json_response[vdi_gateway_list_key]
    if vdi_gateways.empty?
      print_red_alert "VDI Gateway not found by name '#{name}'"
      return nil
    elsif vdi_gateways.size > 1
      print_red_alert "#{vdi_gateways.size} VDI Gateway found by name '#{name}'"
      print_error "\n"
      puts_error as_pretty_table(vdi_gateways, {"ID" => 'id', "NAME" => 'name'}, {color:red})
      print_red_alert "Try using ID instead"
      print_error reset,"\n"
      return nil
    else
      return vdi_gateways[0]
    end
  end


end
