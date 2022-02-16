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
