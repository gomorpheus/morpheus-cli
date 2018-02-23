require 'json'
require 'uri'
require 'rest-client'

class Morpheus::APIClient
  def initialize(access_token, refresh_token=nil,expires_in = nil, base_url=nil, verify_ssl=true) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    if expires_in != nil
      @expires_at = DateTime.now + expires_in.seconds
    end
    set_ssl_verification_enabled(verify_ssl)
  end

  def dry_run(val=true)
    @dry_run = !!val
    self
  end

  def dry()
    dry_run(true)
  end

  def ssl_verification_enabled?
    @verify_ssl
  end

  def set_ssl_verification_enabled(val)
    @verify_ssl = !!val
  end

  def execute(opts, parse_json=true)
    # @verify_ssl is not used atm
    # todo: finish this and use it instead of the global variable RestClient.ssl_verification_enabled?
    # gotta clean up all APIClient subclasses new() methods to support this
    # the CliCommand subclasses should be changed to @users_interface = @api_client.users
    # also.. Credentials.new()
    if @verify_ssl == false
      opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end
    if @dry_run
      # JD: could return a Request object instead...
      return opts
    end
    # Morpheus::Logging::DarkPrinter.puts "Morpheus::RestClient.execute(#{opts})" if Morpheus::Logging.debug?
    # instead, using ::RestClient.log = STDOUT 
    response = Morpheus::RestClient.execute(opts)
    if parse_json
      return JSON.parse(response.to_s)
    else
      return response
    end
  end

  def auth
    Morpheus::AuthInterface.new(@base_url, @access_token)
  end

  def whoami
    Morpheus::WhoamiInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def options
    Morpheus::OptionsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def groups
    Morpheus::GroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def clouds
    Morpheus::CloudsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def servers
    Morpheus::ServersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def instances
    Morpheus::InstancesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def containers
    Morpheus::ContainersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def instance_types
    Morpheus::InstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def provision_types
    Morpheus::ProvisionTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def load_balancers
    Morpheus::LoadBalancersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def tasks
    Morpheus::TasksInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def task_sets
    Morpheus::TaskSetsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def virtual_images
    Morpheus::VirtualImagesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def apps
    Morpheus::AppsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def app_templates
    Morpheus::AppTemplatesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def deploy
    Morpheus::DeployInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def deployments
    Morpheus::DeploymentsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def security_groups
    Morpheus::SecurityGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def security_group_rules
    Morpheus::SecurityGroupRulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def accounts
    Morpheus::AccountsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def users
    Morpheus::UsersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def user_groups
    Morpheus::UserGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def logs
    Morpheus::LogsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def roles
    Morpheus::RolesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def key_pairs
    Morpheus::KeyPairsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def license
    Morpheus::LicenseInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def custom_instance_types
    Morpheus::CustomInstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def option_types
    Morpheus::OptionTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def option_type_lists
    Morpheus::OptionTypeListsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def dashboard
    Morpheus::DashboardInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def setup
    Morpheus::SetupInterface.new(@base_url)
  end
  
  def monitoring
    Morpheus::MonitoringInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  # def checks
  #   # Morpheus::MonitoringChecksInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  #   monitoring.checks
  # end

  # def incidents
  #   # Morpheus::MonitoringIncidentsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  #   monitoring.incidents
  # end

  def policies
    Morpheus::PoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def group_policies
    Morpheus::GroupPoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def cloud_policies
    Morpheus::CloudPoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def networks
    Morpheus::NetworksInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_groups
    Morpheus::NetworkGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_pools
    Morpheus::NetworkPoolsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_services
    Morpheus::NetworkServicesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_pool_servers
    Morpheus::NetworkPoolServersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_domains
    Morpheus::NetworkDomainsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def network_proxies
    Morpheus::NetworkProxiesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def archive_buckets
    Morpheus::ArchiveBucketsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def archive_files
    Morpheus::ArchiveFilesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def image_builder
    Morpheus::ImageBuilderInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def storage_providers
    Morpheus::StorageProvidersInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

end
