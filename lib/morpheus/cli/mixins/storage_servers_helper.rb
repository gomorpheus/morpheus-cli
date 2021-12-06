require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for storage server management
# including storage servers and storage server types
module Morpheus::Cli::StorageServersHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def storage_servers_interface
    # @api_client.storage_servers
    raise "#{self.class} has not defined @storage_servers_interface" if @storage_servers_interface.nil?
    @storage_servers_interface
  end

  def storage_server_types_interface
    # @api_client.storage_server_types
    raise "#{self.class} has not defined @storage_server_types_interface" if @storage_server_types_interface.nil?
    @storage_server_types_interface
  end

  def storage_server_object_key
    'storageServer'
  end

  def storage_server_list_key
    'storageServers'
  end

  def storage_server_label
    'Storage Server'
  end

  def storage_server_label_plural
    'Storage Server'
  end

  def storage_server_type_object_key
    'storageServerType'
  end

  def storage_server_type_list_key
    'storageServerTypes'
  end

  def storage_server_type_label
    'Storage Server Type'
  end

  def storage_server_type_label_plural
    'Storage Server Types'
  end

  def find_storage_server_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_storage_server_by_id(val)
    else
      return find_storage_server_by_name(val)
    end
  end

  def find_storage_server_by_id(id)
    begin
      json_response = storage_servers_interface.get(id.to_i)
      return json_response[storage_server_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Storage Server not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_storage_server_by_name(name)
    lbs = storage_servers_interface.list({name: name.to_s})[storage_server_list_key]
    if lbs.empty?
      print_red_alert "Storage Server not found by name #{name}"
      return nil
    elsif lbs.size > 1
      print_red_alert "#{lbs.size} storage servers found by name #{name}"
      #print_lbs_table(lbs, {color: red})
      print reset,"\n\n"
      return nil
    else
      return lbs[0]
    end
  end

  def get_available_storage_server_types(refresh=false)
    if !@available_storage_server_types || refresh
      @available_storage_server_types = storage_server_types_interface.list({max:1000})[storage_server_type_list_key]
    end
    return @available_storage_server_types
  end

  def storage_server_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return storage_server_type_for_id(val)
    else
      return storage_server_type_for_name(val)
    end
  end

  def storage_server_type_for_id(id)
    return get_available_storage_server_types().find { |z| z['id'].to_i == id.to_i}
  end

  def storage_server_type_for_name(name)
    return get_available_storage_server_types().find { |z| z['name'].downcase == name.downcase || z['code'].downcase == name.downcase}
  end

  def find_storage_server_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_storage_server_type_by_id(val)
    else
      return find_storage_server_type_by_name(val)
    end
  end

  def find_storage_server_type_by_id(id)
    begin
      json_response = storage_server_types_interface.get(id.to_i)
      return json_response[storage_server_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Storage Server Type not found by id #{id}"
        return nil
      else
        raise e
      end
    end
  end

  def find_storage_server_type_by_name(name)
    json_response = storage_server_types_interface.list({name: name.to_s})
    storage_server_types = json_response[storage_server_type_list_key]
    if storage_server_types.empty?
      print_red_alert "Storage Server Type not found by name #{name}"
      return storage_server_types
    elsif storage_server_types.size > 1
      print_red_alert "#{storage_server_types.size} storage server types found by name #{name}"
      rows = storage_server_types.collect do |it|
        {id: it['id'], name: it['name']}
      end
      puts as_pretty_table(rows, [:id, :name], {color:red})
      return nil
    else
      return storage_server_types[0]
    end
  end

end
