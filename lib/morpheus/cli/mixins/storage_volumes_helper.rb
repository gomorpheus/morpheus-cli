require 'morpheus/cli/mixins/print_helper'
require 'morpheus/cli/option_types'
require 'morpheus/rest_client'
# Mixin for Morpheus::Cli command classes
# Provides common methods for storage volume management
# including storage volumes and storage volume types
module Morpheus::Cli::StorageVolumesHelper

  def self.included(klass)
    klass.send :include, Morpheus::Cli::PrintHelper
  end

  def storage_volumes_interface
    # @api_client.storage_volumes
    raise "#{self.class} has not defined @storage_volumes_interface" if @storage_volumes_interface.nil?
    @storage_volumes_interface
  end

  def storage_volume_types_interface
    # @api_client.storage_volume_types
    raise "#{self.class} has not defined @storage_volume_types_interface" if @storage_volume_types_interface.nil?
    @storage_volume_types_interface
  end

  def storage_volume_object_key
    'storageVolume'
  end

  def storage_volume_list_key
    'storageVolumes'
  end

  def storage_volume_label
    'Storage Volume'
  end

  def storage_volume_label_plural
    'Storage Volume'
  end

  def storage_volume_type_object_key
    'storageVolumeType'
  end

  def storage_volume_type_list_key
    'storageVolumeTypes'
  end

  def storage_volume_type_label
    'Storage Volume Type'
  end

  def storage_volume_type_label_plural
    'Storage Volume Types'
  end

  def get_available_storage_volume_types(refresh=false)
    if !@available_storage_volume_types || refresh
      @available_storage_volume_types = storage_volume_types_interface.list({max:1000})[storage_volume_type_list_key]
    end
    return @available_storage_volume_types
  end

  def storage_volume_type_for_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return storage_volume_type_for_id(val)
    else
      return storage_volume_type_for_name(val)
    end
  end

  def storage_volume_type_for_id(val)
    record = get_available_storage_volume_types().find { |z| z['id'].to_i == val.to_i}
    label = "Storage Volume Type"
    if record.nil?
      print_red_alert "#{label} not found by id #{val}"
      return nil
    end
    return record
  end

  def storage_volume_type_for_name(val)
    records = get_available_storage_volume_types().select { |z| z['name'].downcase == val.downcase || z['code'].downcase == val.downcase}
    label = "Storage Volume Type"
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

  def format_storage_volume_status(record, return_color=cyan)
    out = ""
    status_string = record['status']
    if status_string.nil? || status_string.empty? || status_string == "unknown"
      out << "#{white}UNKNOWN#{return_color}"
    elsif status_string == 'provisioned' || status_string == 'unattached'
      out << "#{cyan}#{status_string.capitalize}#{return_color}"
    elsif status_string == 'syncing'
      out << "#{yellow}#{status_string.capitalize}#{return_color}"
    else
      out << "#{red}#{status_string ? status_string.capitalize : 'N/A'}#{record['statusMessage'] ? "#{return_color} - #{record['statusMessage']}" : ''}#{return_color}"
    end
    out
  end

  def format_storage_volume_source(storage_volume)
    storage_volume['source']
  end

end
