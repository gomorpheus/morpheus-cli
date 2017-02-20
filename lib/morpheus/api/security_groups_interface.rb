require 'morpheus/api/api_client'

class Morpheus::SecurityGroupsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def list(options=nil)
		url = "#{@base_url}/api/security-groups"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		if options.is_a?(Hash)
			headers[:params].merge!(options)
		end
		execute(method: :get, url: url, headers: headers)
	end

	def get(options)
		url = "#{@base_url}/api/security-groups/#{options[:id]}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		if options.is_a?(Hash)
			headers[:params].merge!(options)
		end
		execute(method: :get, url: url, headers: headers)
	end

	def create(options)
		url = "#{@base_url}/api/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :post, url: url, headers: headers, payload: payload.to_json)
	end

	def update(id)
		url = "#{@base_url}/api/security-groups/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :put, url: url, headers: headers)
	end

	def delete(id)
		url = "#{@base_url}/api/security-groups/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :delete, url: url, headers: headers)
	end
end
