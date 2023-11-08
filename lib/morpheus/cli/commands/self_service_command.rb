require 'morpheus/cli/cli_command'
require 'morpheus/cli/commands/catalog_item_types_command'

class Morpheus::Cli::SelfServiceCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'self-service'
  set_command_description "Deprecated and replaced by catalog-item-types"

  set_command_hidden
  
  def handle(args)
  	print_error yellow,"[DEPRECATED] The command `self-service` is deprecated and replaced by `catalog-item-types`.",reset,"\n"
  	Morpheus::Cli::CatalogItemTypesCommand.new.handle(args)
  end

end
