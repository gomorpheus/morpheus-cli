require 'json'
require 'morpheus/rest_client'

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
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def create(options)
		url = "#{@base_url}/api/apps"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                                                     timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def update(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :put, url: url,
                                                     timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def add_instance(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}/add-instance"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                                                     timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def remove_instance(app_id, options)
		url = "#{@base_url}/api/apps/#{app_id}/remove-instance"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                                                     timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/apps/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                                                     timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

=begin
	def stop(id)
		url = "#{@base_url}/api/apps/#{id}/stop"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                                                     timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def start(id)
		url = "#{@base_url}/api/apps/#{id}/start"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                                                     timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def restart(id)
		url = "#{@base_url}/api/apps/#{id}/restart"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                                                     timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end
=end

	def firewall_disable(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups/disable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def firewall_enable(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups/enable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def security_groups(id)
		url = "#{@base_url}/api/apps/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def apply_security_groups(id, options)
		url = "#{@base_url}/api/apps/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end
end
