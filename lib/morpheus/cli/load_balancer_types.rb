# require 'yaml'
require 'io/console'
require 'rest_client'
require 'optparse'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancer-types'
  register_subcommands :list, :get

  register_interfaces :load_balancer_types

  protected

  def load_balancer_type_list_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code'
    }
  end

  def load_balancer_type_column_definitions()
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code'
    }
  end

  # overridden to work with name or code
  def find_load_balancer_type_by_name_or_id(name)
    load_balancer_type_for_name_or_id(name)
  end

end

