require 'json'
require 'uri'
require 'rest-client'

class Morpheus::APIClient
	def initialize(access_token, refresh_token=nil,expires_in = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		if expires_in != nil
			@expires_at = DateTime.now + expires_in.seconds
		end
	end

	def dry_run(val=true)
		@dry_run = !!val
		self
	end

	def dry()
		dry_run(true)
	end

	def execute(opts, parse_json=true)
		if @dry_run
			# JD: could return a Request object instead...
			return opts
		end
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

	def dashboard
		Morpheus::DashboardInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end

end
