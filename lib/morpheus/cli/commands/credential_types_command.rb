require 'morpheus/cli/cli_command'

class Morpheus::Cli::CredentialTypesCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_description "View credential types"
  set_command_name :'credential-types'
  register_subcommands :list, :get

  # register_interfaces :credential_types

  protected

  def credential_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def credential_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      # "Description" => 'description',
      "Enabled" => lambda {|it| format_boolean(it['enabled']) },
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
      "Editable" => lambda {|it| format_boolean(it['editable']) },
    }
  end

end

