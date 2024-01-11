require 'morpheus/cli/cli_command'

class Morpheus::Cli::BackupTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand

  set_command_description "View backup types."
  set_command_name :'backup-types'
  register_subcommands :list, :get
  register_interfaces :backup_types

  # This is a hidden command, could move to backup list-types and backup get-type
  set_command_hidden

  protected

  def backup_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      # "Active" => lambda {|it| format_boolean it['active'] },
      # "Provider Code" => 'providerCode',
    }
  end

  def backup_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      #"Backup Format" => 'backupFormat',
      "Active" => lambda {|it| format_boolean it['active'] },
      # "Container Type" => 'containerType',
      # "Container Format" => 'containerFormat',
      # "Container Category" => 'containerCategory',
      "Restore Type" => 'restoreType',
      # "Has Stream To Store" => lambda {|it| format_boolean it['hasStreamToStore'] },
      # "Has Copy To Store" => lambda {|it| format_boolean it['hasCopyToStore'] },
      "Download" => lambda {|it| format_boolean it['downloadEnabled'] },
      # "Download From Store Only" => lambda {|it| format_boolean it['downloadFromStoreOnly'] },
      # "Copy To Store" => lambda {|it| format_boolean it['copyToStore'] },
      "Restore Existing" => lambda {|it| format_boolean it['restoreExistingEnabled'] },
      "Restore New" => lambda {|it| format_boolean it['restoreNewEnabled'] },
      # "Restore New Mode" => 'restoreNewMode',
      # "Prune Results On Restore Existing" => lambda {|it| format_boolean it['pruneResultsOnRestoreExisting'] },
      # "Restrict Targets" => lambda {|it| format_boolean it['restrictTargets'] },
      # "Provider Code" => 'providerCode',
      "Plugin" => lambda {|it| format_boolean it['isPlugin'] },
      "Embedded" => lambda {|it| format_boolean it['isEmbedded'] },
    }
  end
end