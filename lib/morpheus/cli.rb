require 'morpheus/cli/version'
require 'morpheus/cli/errors'
require 'morpheus/rest_client'
require 'morpheus/formatters'
require 'morpheus/logging'
require 'morpheus/util'
require 'term/ansicolor'

Dir[File.dirname(__FILE__)  + "/ext/*.rb"].each {|file| require file }

module Morpheus
  module Cli
    
    # get the home directory, where morpheus-cli stores things   
    # The default is $MORPHEUS_CLI_HOME or $HOME/.morpheus
    unless defined?(@@home_directory)
      @@home_directory = ENV['MORPHEUS_CLI_HOME'] || File.join(Dir.home, ".morpheus")
    end
    
    def self.home_directory
      @@home_directory
    end

    # set the home directory
    def self.home_directory=(fn)
      @@home_directory = fn
    end

    # check if this is a Windows environment.
    def self.windows?
      if defined?(@@is_windows)
        return @@is_windows
      end
      @@is_windows = false
      begin
        require 'rbconfig'
        @@is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)
      rescue => ex
        # $stderr.puts "unable to determine if this is a Windows machine."
      end
      return @@is_windows
    end

    # load all the well known commands and utilties they need
    def self.load!()
      # load interfaces
      require 'morpheus/api/api_client.rb'
      require 'morpheus/api/rest_interface.rb'
      require 'morpheus/api/read_interface.rb'
      Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each {|file| load file }

      # load mixins
      Dir[File.dirname(__FILE__)  + "/cli/mixins/*.rb"].each {|file| load file }

      # load commands
      # Dir[File.dirname(__FILE__)  + "/cli/*.rb"].each {|file| load file }

      # utilites
      require 'morpheus/cli/cli_registry.rb'
      require 'morpheus/cli/expression_parser.rb'
      require 'morpheus/cli/dot_file.rb'
      require 'morpheus/cli/errors'

      load 'morpheus/cli/cli_command.rb'
      load 'morpheus/cli/option_types.rb'
      load 'morpheus/cli/credentials.rb'
      
      # all standard commands
      Dir[File.dirname(__FILE__)  + "/cli/commands/standard/**/*.rb"].each {|file| load file }

      # all the known commands
      load 'morpheus/cli/remote.rb'
      load 'morpheus/cli/doc.rb'
      load 'morpheus/cli/ping.rb'
      load 'morpheus/cli/setup.rb'
      load 'morpheus/cli/login.rb'
      load 'morpheus/cli/logout.rb'
      load 'morpheus/cli/forgot_password.rb'
      load 'morpheus/cli/whoami.rb'
      load 'morpheus/cli/access_token_command.rb'
      load 'morpheus/cli/user_settings_command.rb'
      load 'morpheus/cli/search_command.rb'
      load 'morpheus/cli/dashboard_command.rb'
      load 'morpheus/cli/recent_activity_command.rb' # deprecated, removing soon
      load 'morpheus/cli/activity_command.rb'
      load 'morpheus/cli/appliance_settings_command.rb'
      load 'morpheus/cli/power_schedules_command.rb'
      load 'morpheus/cli/execute_schedules_command.rb'
      load 'morpheus/cli/groups.rb'
      load 'morpheus/cli/clouds.rb'
      load 'morpheus/cli/cloud_datastores_command.rb'
      load 'morpheus/cli/cloud_resource_pools_command.rb'
      load 'morpheus/cli/cloud_folders_command.rb'
      load 'morpheus/cli/hosts.rb'
      load 'morpheus/cli/load_balancers.rb'
      load 'morpheus/cli/shell.rb'
      load 'morpheus/cli/tasks.rb'
      load 'morpheus/cli/workflows.rb'
      load 'morpheus/cli/deployments.rb'
      load 'morpheus/cli/deploy.rb'
      load 'morpheus/cli/deploys.rb'
      load 'morpheus/cli/instances.rb'
      load 'morpheus/cli/containers_command.rb'
      load 'morpheus/cli/apps.rb'
      load 'morpheus/cli/blueprints_command.rb'
      load 'morpheus/cli/license.rb'
      load 'morpheus/cli/instance_types.rb'
      load 'morpheus/cli/jobs_command.rb'
      load 'morpheus/cli/integrations_command.rb'
      load 'morpheus/cli/security_groups.rb'
      load 'morpheus/cli/security_group_rules.rb'
      load 'morpheus/cli/clusters.rb'
      load 'morpheus/cli/tenants_command.rb'
      load 'morpheus/cli/account_groups_command.rb'
      load 'morpheus/cli/users.rb'
      load 'morpheus/cli/change_password_command.rb'
      load 'morpheus/cli/user_groups_command.rb'
      load 'morpheus/cli/user_sources_command.rb'
      load 'morpheus/cli/roles.rb'
      load 'morpheus/cli/key_pairs.rb'
      load 'morpheus/cli/virtual_images.rb'
      # load 'morpheus/cli/library.rb' # gone until we collapse these again
      load 'morpheus/cli/library_instance_types_command.rb'
      load 'morpheus/cli/library_cluster_layouts_command.rb'
      load 'morpheus/cli/library_layouts_command.rb'
      load 'morpheus/cli/library_upgrades_command.rb'
      load 'morpheus/cli/library_container_types_command.rb'
      load 'morpheus/cli/library_container_scripts_command.rb'
      load 'morpheus/cli/library_container_templates_command.rb'
      load 'morpheus/cli/library_option_types_command.rb'
      load 'morpheus/cli/library_option_lists_command.rb'
      load 'morpheus/cli/library_spec_templates_command.rb'
      load 'morpheus/cli/monitoring_incidents_command.rb'
      load 'morpheus/cli/monitoring_checks_command.rb'
      load 'morpheus/cli/monitoring_contacts_command.rb'
      load 'morpheus/cli/monitoring_alerts_command.rb'
      load 'morpheus/cli/monitoring_groups_command.rb'
      load 'morpheus/cli/monitoring_apps_command.rb'
      load 'morpheus/cli/logs_command.rb'
      load 'morpheus/cli/policies_command.rb'
      load 'morpheus/cli/networks_command.rb'
      load 'morpheus/cli/subnets_command.rb'
      load 'morpheus/cli/network_groups_command.rb'
      load 'morpheus/cli/network_pools_command.rb'
      load 'morpheus/cli/network_services_command.rb'
      load 'morpheus/cli/network_pool_servers_command.rb'
      load 'morpheus/cli/network_domains_command.rb'
      load 'morpheus/cli/network_proxies_command.rb'
      load 'morpheus/cli/network_routers_command.rb'
      load 'morpheus/cli/cypher_command.rb'
      load 'morpheus/cli/image_builder_command.rb'
      load 'morpheus/cli/preseed_scripts_command.rb'
      load 'morpheus/cli/boot_scripts_command.rb'
      load 'morpheus/cli/archives_command.rb'
      load 'morpheus/cli/storage_providers_command.rb'
      load 'morpheus/cli/execution_request_command.rb'
      load 'morpheus/cli/file_copy_request_command.rb'
      load 'morpheus/cli/processes_command.rb'
      load 'morpheus/cli/packages_command.rb'
      load 'morpheus/cli/reports_command.rb'
      load 'morpheus/cli/environments_command.rb'
      load 'morpheus/cli/backup_settings_command.rb'
      load 'morpheus/cli/log_settings_command.rb'
      load 'morpheus/cli/whitelabel_settings_command.rb'
      load 'morpheus/cli/wiki_command.rb'
      load 'morpheus/cli/approvals_command.rb'
      load 'morpheus/cli/service_plans_command.rb'
      load 'morpheus/cli/price_sets_command.rb'
      load 'morpheus/cli/prices_command.rb'
      load 'morpheus/cli/provisioning_settings_command.rb'
      load 'morpheus/cli/provisioning_licenses_command.rb'
      load 'morpheus/cli/budgets_command.rb'
      load 'morpheus/cli/health_command.rb'
      load 'morpheus/cli/invoices_command.rb'
      load 'morpheus/cli/guidance_command.rb'
      load 'morpheus/cli/projects_command.rb'
      load 'morpheus/cli/backups_command.rb'
      load 'morpheus/cli/backup_jobs_command.rb'
      load 'morpheus/cli/catalog_item_types_command.rb' # self-service
      load 'morpheus/cli/service_catalog_command.rb' # catalog (Service Catalog persona)
      load 'morpheus/cli/usage_command.rb'
      load 'morpheus/cli/vdi_pools_command.rb'
      load 'morpheus/cli/vdi_apps_command.rb'
      load 'morpheus/cli/vdi_gateways_command.rb'
      load 'morpheus/cli/vdi_command.rb' # (VDI persona)
      # add new commands here...

    end

    load!
    
  end

end
