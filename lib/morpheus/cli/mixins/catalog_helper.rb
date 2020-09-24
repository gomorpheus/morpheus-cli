require 'morpheus/cli/mixins/print_helper'
# Mixin for Morpheus::Cli command classes
# Provides common methods for infrastructure management
module Morpheus::Cli::CatalogHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def catalog_item_types_interface
    raise "#{self.class} has not defined @catalog_item_types_interface" if @catalog_item_types_interface.nil?
    @catalog_item_types_interface
  end

  # def service_catalog_interface
  #   raise "#{self.class} has not defined @service_catalog_interface" if @service_catalog_interface.nil?
  #   @service_catalog_interface
  # end

  def catalog_item_type_object_key
    'catalogItemType'
  end

  def catalog_item_type_list_key
    'catalogItemTypes'
  end

  def find_catalog_item_type_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_catalog_item_type_by_id(val)
    else
      return find_catalog_item_type_by_name(val)
    end
  end

  def find_catalog_item_type_by_id(id)
    begin
      json_response = catalog_item_types_interface.get(id.to_i)
      return json_response[catalog_item_type_object_key]
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "catalog_item_type not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_catalog_item_type_by_name(name)
    json_response = catalog_item_types_interface.list({name: name.to_s})
    catalog_item_types = json_response[catalog_item_type_list_key]
    if catalog_item_types.empty?
      print_red_alert "catalog_item_type not found by name '#{name}'"
      return nil
    elsif catalog_item_types.size > 1
      print_red_alert "#{catalog_item_types.size} catalog_item_types found by name '#{name}'"
      puts_error as_pretty_table(catalog_item_types, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return catalog_item_types[0]
    end
  end

end
