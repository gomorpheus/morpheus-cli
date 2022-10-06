require 'morpheus/cli/cli_command'

class Morpheus::Cli::SecurityPackageTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_description "View security_package types"
  set_command_name :'security-package-types'
  register_subcommands :list, :get

  # register_interfaces :security_package_types

  protected

  def security_package_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def security_package_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

end

