require 'morpheus/cli/cli_command'

class Morpheus::Cli::LoadBalancerProfiles
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::RestCommand
  include Morpheus::Cli::SecondaryRestCommand
  include Morpheus::Cli::LoadBalancersHelper

  set_command_description "View and manage load balancer profiles."
  set_command_name :'load-balancer-profiles'
  register_subcommands :list, :get, :add, :update, :remove
  register_interfaces :load_balancer_profiles,
                      :load_balancers, :load_balancer_types

  set_rest_parent_name :load_balancers

  protected

  def load_balancer_profile_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      # "Profile Type" => lambda {|it| it['config']['profileType'] rescue '' },
      "Service Type" => lambda {|it| it['serviceTypeDisplay'] || it['serviceType'] },
    }
  end

  def load_balancer_profile_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Load Balancer" => lambda {|it| it['loadBalancer'] ? it['loadBalancer']['name'] : '' },
      "Description" => 'description',
      # "Profile Type" => lambda {|it| it['config']['profileType'] rescue '' },
      "Service Type" => lambda {|it| it['serviceTypeDisplay'] || it['serviceType'] },
      "Created" => lambda {|it| format_local_dt(it['dateCreated']) },
      "Updated" => lambda {|it| format_local_dt(it['lastUpdated']) }
    }
  end

  def load_balancer_profile_object_key
    'loadBalancerProfile'
  end

  def load_balancer_profile_list_key
    'loadBalancerProfiles'
  end

  def load_balancer_profile_label
    'Load Balancer Profile'
  end

  def load_balancer_profile_label_plural
    'Load Balancer Profiles'
  end

  def load_option_types_for_load_balancer_profile(type_record, parent_record)
    load_balancer = parent_record
    load_balancer_type_id = load_balancer['type']['id']
    load_balancer_type = find_by_id(:load_balancer_type, load_balancer_type_id)
    load_balancer_type['profileOptionTypes']
  end

end
