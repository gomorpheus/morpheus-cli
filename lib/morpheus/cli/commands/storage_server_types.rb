require 'morpheus/cli/cli_command'

class Morpheus::Cli::StorageServerTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::StorageServersHelper

  set_command_description "View storage server types"
  set_command_name :'storage-server-types'
  register_subcommands :list, :get

  # register_interfaces :storage_server_types

  protected

  def storage_server_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
    }
  end

  def storage_server_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Description" => 'description',
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
      "Create Namespaces" => lambda {|it| format_boolean(it['createNamespaces']) },
      "Create Groups" => lambda {|it| format_boolean(it['createGroups']) },
      "Create Hosts" => lambda {|it| format_boolean(it['createHosts']) },
      "Create Disks" => lambda {|it| format_boolean(it['createDisks']) },
      "Has Namespaces" => lambda {|it| format_boolean(it['hasNamespaces']) },
      "Has Groups" => lambda {|it| format_boolean(it['hasGroups']) },
      "Has Hosts" => lambda {|it| format_boolean(it['hasHosts']) },
      "Has Disks" => lambda {|it| format_boolean(it['hasDisks']) },
      "Has File Browser" => lambda {|it| format_boolean(it['hasFileBrowser']) },
    }
  end

  # overridden to support name or code
  def find_storage_server_type_by_name_or_id(name)
    storage_server_type_for_name_or_id(name)
  end

end

