require 'morpheus/cli/cli_command'
require 'morpheus/cli/mixins/monitoring_helper'

class Morpheus::Cli::MonitoringAppsCommand
  include Morpheus::Cli::CliCommand
  include Morpheus::Cli::MonitoringHelper

  set_command_name :'check-apps'
  register_subcommands :list, :get, :add, :update, :remove, :quarantine, :history, :statistics
  set_default_subcommand :list
  
  set_command_hidden # remove me when implemented

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @monitoring_interface = Morpheus::APIClient.new(@access_token,nil,nil, @appliance_url).monitoring
  end

  def handle(args)
    handle_subcommand(args)
  end

  # todo: API updates and subcommands

end
