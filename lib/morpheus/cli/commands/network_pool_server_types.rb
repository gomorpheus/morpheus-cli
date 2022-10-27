require 'morpheus/cli/cli_command'

class Morpheus::Cli::NetworkPoolServerTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::InfrastructureHelper

  set_command_description "View network pool server types"
  set_command_name :'network-pool-server-types'
  register_subcommands :list, :get

  # hidden in favor of get-type and list-types
  set_command_hidden

  # register_interfaces :network_pool_server_types

  protected

end

