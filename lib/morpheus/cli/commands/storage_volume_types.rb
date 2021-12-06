require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageVolumeTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageVolumesHelper

  set_command_name :'storage-volume-types'
  register_subcommands :list, :get

  # register_interfaces :storage_volume_types

  protected

  def storage_volume_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
    }
  end

  def storage_volume_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
    }
  end

  # overridden to support name or code
  def find_storage_volume_type_by_name_or_id(name)
    storage_volume_type_for_name_or_id(name)
  end

end

