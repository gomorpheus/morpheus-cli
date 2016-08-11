require "morpheus/cli/version"
require "morpheus/rest_client"

module Morpheus
  module Cli
  	require 'morpheus/api/api_client'
  	require 'morpheus/api/groups_interface'
  	require 'morpheus/api/clouds_interface'
  	require 'morpheus/api/servers_interface'
  	require 'morpheus/api/instances_interface'
    require 'morpheus/api/instance_types_interface'
    require 'morpheus/api/apps_interface'
    require 'morpheus/api/deploy_interface'
    require 'morpheus/api/security_groups_interface'
    require 'morpheus/api/security_group_rules_interface'
  	require 'morpheus/cli/credentials'
  	require 'morpheus/cli/error_handler'
  	require 'morpheus/cli/remote'
  	require 'morpheus/cli/groups'
  	require 'morpheus/cli/clouds'
  	require 'morpheus/cli/servers'
    require 'morpheus/cli/instances'
    require 'morpheus/cli/apps'
    require 'morpheus/cli/deploys'
    require 'morpheus/cli/instance_types'
    require 'morpheus/cli/security_groups'
    require 'morpheus/cli/security_group_rules'
    # Your code goes here...
  end
end
