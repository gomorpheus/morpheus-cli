require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerTypes
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_name :'load-balancer-types'
  register_subcommands :list, :get

  # register_interfaces :load_balancer_types

  protected

  def load_balancer_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def load_balancer_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
    }
  end

  # overridden to support name or code
  def find_load_balancer_type_by_name_or_id(name)
    load_balancer_type_for_name_or_id(name)
  end

end

