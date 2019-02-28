require 'json'
require 'uri'
require 'rest-client'

class Morpheus::APIClient
  def initialize(access_token, refresh_token=nil,expires_in = nil, base_url=nil, verify_ssl=true, options={})
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    if expires_in != nil
      @expires_at = DateTime.now + expires_in.seconds
    end
    set_ssl_verification_enabled(verify_ssl)
    setopts(options)
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

  # common global options, hooray.
  # this is probably needed for CliCommand too..
  # maybe make this a mixin...

  # need this accessor?
  # def get_options
  #   @options
  # end

  # set common global @options for use with all requests
  # meant for inline use just like dry(), set_options(dry_run:true) can be used in place of dry()
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # Example: 
  # Prints curl -XGET .../whoami -H "Bearer" instead of actually request
  # APIClient.new(token).whoami.setopts(curl:true).get({})
  # @return self (APIClient)
  def setopts(new_options)
    @options = new_options
    if @options[:dry_run]
      dry_run(true)
    end
    self
  end

  # with_options sets common global @options for the duration of the block only
  # then returns the options to their prior values
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # @return result of block, usually the a result Hash from client.execute({})
  def withopts(tmp_options, &block)
    @_old_options = @options
    begin
      @options = tmp_options
      result = block.call()
    ensure
      @options = @_old_options
    end
    return result
  end

  alias :set_options :setopts
  alias :with_options :withopts
  # Execute an HTTP request with this client.
  # opts - Hash of options for HTTP Request.
  #   :url - The full url
  #   :method - The default method is :get (GET)
  #   :headers - Hash of headers to include in the request.
  #              eg. {'Content-Type' => 'application/json'}. :params is a special key for query parameters.
  #   :params - query parameters
  #   :payload - The body of the request.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  # options - Hash of common global options that commands parse. eg. :headers, :timeout, :dry_run, :curl, etc
  #   :headers - Extra headers to add. This expects a Hash like {'Content-Type' => 'application/json'}.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  def execute(opts, options={})
    # merge in common global @options
    if @options
      options = options.merge(@options)
    else
      options = options.clone
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
    if options[:timeout]
      opts[:timeout] = options[:timeout].to_f
    end
    
    # add extra headers, eg. from --header option
    # headers should be a Hash and not an Array, dont make me split you here!
    if options[:headers]
      opts[:headers] = opts[:headers].merge(options[:headers])
    end

    # this is confusing, but RestClient expects :params inside the headers...?
    # right?
    # move/copy params to headers.params for simplification.
    # remove this if issues arise
    if opts[:params] && (opts[:headers][:params].nil? || opts[:headers][:params].empty?)
      opts[:headers][:params] = opts[:params] # .delete(:params) maybe?
    end

    # :command_options for these
    # if options[:curl]
    #   opts[:curl] = options[:curl]
    # end
    # if options.key?(:pretty_json)
    #   opts[:pretty_json] = options[:pretty_json]
    # end
    # if options.key?(:scrub)
    #   opts[:scrub] = options[:scrub]
    # end

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
      # print_dry_run needs options somehow...
      opts[:command_options] = options # trash this..we got @options with setopts now
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
    if opts[:parse_json] != false && options[:parse_json] != false
      return JSON.parse(response.to_s)
    else
      return response
    end
  end

  def auth
    Morpheus::AuthInterface.new(@base_url, @access_token).setopts(@options)
  end

  def whoami
    Morpheus::WhoamiInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def user_settings
    Morpheus::UserSettingsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def options
    Morpheus::OptionsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def groups
    Morpheus::GroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def account_groups
    Morpheus::AccountGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def clouds
    Morpheus::CloudsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def cloud_datastores
    Morpheus::CloudDatastoresInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def servers
    Morpheus::ServersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def instances
    Morpheus::InstancesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def containers
    Morpheus::ContainersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def instance_types
    Morpheus::InstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def server_types
    Morpheus::ServerTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def provision_types
    Morpheus::ProvisionTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def load_balancers
    Morpheus::LoadBalancersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def tasks
    Morpheus::TasksInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def task_sets
    Morpheus::TaskSetsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def virtual_images
    Morpheus::VirtualImagesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def apps
    Morpheus::AppsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def blueprints
    Morpheus::BlueprintsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def deploy
    Morpheus::DeployInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def deployments
    Morpheus::DeploymentsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def security_groups
    Morpheus::SecurityGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def security_group_rules
    Morpheus::SecurityGroupRulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def accounts
    Morpheus::AccountsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def users
    Morpheus::UsersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def user_groups
    Morpheus::UserGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def user_sources
    Morpheus::UserSourcesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def logs
    Morpheus::LogsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def roles
    Morpheus::RolesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def key_pairs
    Morpheus::KeyPairsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def license
    Morpheus::LicenseInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def custom_instance_types
    Morpheus::CustomInstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def option_types
    Morpheus::OptionTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def option_type_lists
    Morpheus::OptionTypeListsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def dashboard
    Morpheus::DashboardInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def power_schedules
    Morpheus::PowerSchedulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def execute_schedules
    Morpheus::ExecuteSchedulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def setup
    Morpheus::SetupInterface.new(@base_url).setopts(@options).setopts(@options)
  end
  
  def monitoring
    Morpheus::MonitoringInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  # def checks
  #   # Morpheus::MonitoringChecksInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  #   monitoring.checks
  # end

  # def incidents
  #   # Morpheus::MonitoringIncidentsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  #   monitoring.incidents
  # end

  def policies
    Morpheus::PoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def group_policies
    Morpheus::GroupPoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def cloud_policies
    Morpheus::CloudPoliciesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def networks
    Morpheus::NetworksInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_groups
    Morpheus::NetworkGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_pools
    Morpheus::NetworkPoolsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_services
    Morpheus::NetworkServicesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_pool_servers
    Morpheus::NetworkPoolServersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_domains
    Morpheus::NetworkDomainsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def network_proxies
    Morpheus::NetworkProxiesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def archive_buckets
    Morpheus::ArchiveBucketsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def archive_files
    Morpheus::ArchiveFilesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def image_builder
    Morpheus::ImageBuilderInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def storage_providers
    Morpheus::StorageProvidersInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_instance_types
    Morpheus::LibraryInstanceTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_layouts
    Morpheus::LibraryLayoutsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_container_upgrades
    Morpheus::LibraryContainerUpgradesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_container_types
    Morpheus::LibraryContainerTypesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_container_scripts
    Morpheus::LibraryContainerScriptsInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def library_container_templates
    Morpheus::LibraryContainerTemplatesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def packages
    Morpheus::PackagesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def cypher
    Morpheus::CypherInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def old_cypher
    Morpheus::OldCypherInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end
  
  def execution_request
    Morpheus::ExecutionRequestInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def file_copy_request
    Morpheus::FileCopyRequestInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  def processes
    Morpheus::ProcessesInterface.new(@access_token, @refresh_token, @expires_at, @base_url).setopts(@options)
  end

  # new interfaces get added here

end
