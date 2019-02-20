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

  # set this in your interface, eg. to 'application/json'
  def default_content_type
    nil
  end

  # Execute an HTTP request with this client.
  # opts - Hash of options for HTTP Request.
  #   :url - The full url
  #   :method - The default method is :get (GET)
  #   :headers - Hash of headers to include in the request.
  #              eg. {'Content-Type' => 'application/json'}. :params is a special key for query parameters.
  #   :params - query parameters
  #   :payload - The body of the request.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  # options - Hash of common options that commands parse. eg. :headers, :timeout
  #   :headers - Extra headers to add. This expects a Hash like {'Content-Type' => 'application/json'}.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  def execute(opts, options={})

    # Parsed api response as JSON? 
    # True by default. 
    # Pass parse_json:false to avoid that. ie. you do not expect JSON back
    # todo: get rid of this behavior..make parsing the caller responsibility, 
    #       or atleast check the Content-Type of the result.. 
    # ok .. the second argument used to be 'parse_json' (boolean) which is true by default
    # so still support it that way until we can update those interface methods to use parse_json:false
    parse_json = true
    if options == true || options == false
      parse_json = options
      options = {}
    end
    if opts[:parse_json] == false || options[:parse_json] == false
      parse_json = false
    end

    # default HTTP method
    if opts[:method].nil?
      # why not a default? you will get an error from RestClient
      # opts[:method] = :get
    else
      # convert to lowercase Symbol like :get, :post, :put, or :delete
      opts[:method] = opts[:method].to_s.downcase.to_sym
    end

    # apply default headers
    opts[:headers] ||= {}
    # Authorization: apply our access token
    if @access_token
      if opts[:headers][:authorization].nil? && opts[:headers]['Authorization'].nil?
        opts[:headers][:authorization] = "Bearer #{@access_token}"
      else
        # authorization header has already been set.
      end
    end

    # Content-Type: apply interface default
    if opts[:headers]['Content-Type'].nil? && default_content_type
      opts[:headers]['Content-Type'] = default_content_type
    end

    # use custom timeout eg. from --timeout option
    opts[:timeout] = options[:timeout].to_f if options[:timeout]
    
    # add extra headers, eg. from --header option
    # headers should be a Hash and not an Array, dont make me split you here!
    opts[:headers].merge(options[:headers]) if options[:headers]

    # this is confusing, but RestClient expects :params inside the headers...?
    # right?
    # move/copy params to headers.params for simplification.
    # remove this if issues arise
    if opts[:params] && (opts[:headers][:params].nil? || opts[:headers][:params].empty?)
      opts[:headers][:params] = opts[:params] # .delete(:params) maybe?
    end

    # curl output for dry run?
    if options[:curl]
      opts[:curl] = options[:curl]
    end

    # not working when combining with curl, fix it!
    if options.key?(:pretty_json) == false
      opts[:pretty_json] = options[:pretty_json]
    end

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

    # uhh can't use LIST at the moment
    # fix it!
    # if opts[:method] == :list
    #   opts[:method]
    # end

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

  def user_settings
    Morpheus::UserSettingsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def options
    Morpheus::OptionsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def groups
    Morpheus::GroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def account_groups
    Morpheus::AccountGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def clouds
    Morpheus::CloudsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def cloud_datastores
    Morpheus::CloudDatastoresInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
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

  def blueprints
    Morpheus::BlueprintsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
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

  def user_sources
    Morpheus::UserSourcesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
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

  def power_schedules
    Morpheus::PowerSchedulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def execute_schedules
    Morpheus::ExecuteSchedulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
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

  def library_instance_types
    Morpheus::LibraryInstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def library_layouts
    Morpheus::LibraryLayoutsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def library_container_upgrades
    Morpheus::LibraryContainerUpgradesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def library_container_types
    Morpheus::LibraryContainerTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def library_container_scripts
    Morpheus::LibraryContainerScriptsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def library_container_templates
    Morpheus::LibraryContainerTemplatesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def packages
    Morpheus::PackagesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def cypher
    Morpheus::CypherInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def cypher_vault
    Morpheus::CypherVaultInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end
  
  def execution_request
    Morpheus::ExecutionRequestInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def file_copy_request
    Morpheus::FileCopyRequestInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  def processes
    Morpheus::ProcessesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
  end

  # ^ + add new interfaces here

end
