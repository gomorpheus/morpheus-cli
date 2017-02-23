require 'morpheus/api/api_client'

class Morpheus::CloudsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def cloud_types()
		url = "#{@base_url}/api/zone-types"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		opts = {method: :get, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def get(options=nil)
		url = "#{@base_url}/api/zones"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/zones/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		opts = {method: :get, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def create(options)
		url = "#{@base_url}/api/zones"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, timeout: 30, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def update(id, options)
		url = "#{@base_url}/api/zones/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def destroy(id, params={})
		url = "#{@base_url}/api/zones/#{id}"
		headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :delete, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def firewall_disable(id)
		url = "#{@base_url}/api/zones/#{id}/security-groups/disable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def firewall_enable(id)
		url = "#{@base_url}/api/zones/#{id}/security-groups/enable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def security_groups(id)
		url = "#{@base_url}/api/zones/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :get, url: url, timeout: 30, headers: headers}
		execute(opts)
	end

	def apply_security_groups(id, options)
		url = "#{@base_url}/api/zones/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, timeout: 30, headers: headers, payload: payload.to_json}
		execute(opts)
	end
end
