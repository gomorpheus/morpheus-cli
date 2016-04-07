require 'json'
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

	def groups
		Morpheus::GroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end

	def zones
		Morpheus::ZonesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
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

	def apps
		Morpheus::AppsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end

	def deploy
		Morpheus::DeployInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end

	def security_groups
		Morpheus::SecurityGroupsInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end

	def security_group_rules
		Morpheus::SecurityGroupRulesInterface.new(@access_token, @refresh_token, @expires_at, @base_url)
	end
end