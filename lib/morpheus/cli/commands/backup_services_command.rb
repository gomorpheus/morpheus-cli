require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupServices
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_description "View and manage backup services."
  set_command_name :'backup-services'
  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :backup_services, :backup_service_types
  set_rest_has_type true

  protected

  def load_option_types_for_backup_service(record_type, parent_record)
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'required' => true, 'displayOrder' => 1},
      {'fieldName' => 'enabled', 'fieldLabel' => 'Enabled', 'type' => 'checkbox', 'defaultValue' => 'on', 'displayOrder' => 2},
      {'fieldName' => 'visibility', 'fieldLabel' => 'Visibility', 'type' => 'select', 'selectOptions' => [{'name' => 'Public', 'value' => 'public'}, {'name' => 'Private', 'value' => 'private'}], 'defaultValue' => 'public', 'displayOrder' => 1000}
    ] + record_type['optionTypes']
  end

  def backup_service_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Status" => 'status',
      "Visibility" => 'visibility'
    }
  end

  def backup_service_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Enabled" => 'enabled',
      "Api URL" => 'serviceUrl',
      "Host" => 'host',
      "Port" => 'port',
      "Credential" => lambda {|it| it['credential']['type'] == 'local' ? 'local' : it['credential']['name']},
      "Visibility" => 'visibility'
    }
  end
end