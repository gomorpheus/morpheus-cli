require 'morpheus/api/api_client'

class Morpheus::AppsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(options=nil)
		url = "#{@base_url}/api/apps"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/apps/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def create(options)
		url = "#{@base_url}/api/apps"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def update(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def add_instance(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}/add-instance"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def remove_instance(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}/remove-instance"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def destroy(id)
		url = "#{@base_url}/api/apps/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :delete, url: url, headers: headers}
		execute(opts)
	end

	def stop(id)
		url = "#{@base_url}/api/apps/#{id}/stop"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, headers: headers}
		execute(opts)
	end

	def start(id)
		url = "#{@base_url}/api/apps/#{id}/start"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, headers: headers}
		execute(opts)
	end

	def restart(id)
		url = "#{@base_url}/api/apps/#{id}/restart"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, headers: headers}
		execute(opts)
	end

	def firewall_disable(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups/disable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, headers: headers}
		execute(opts)
	end

	def firewall_enable(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups/enable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :put, url: url, headers: headers}
		execute(opts)
	end

	def security_groups(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def apply_security_groups(id, options)
		url = "#{@base_url}/api/apps/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end
end
