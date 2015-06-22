require 'json'
require 'rest-client'

class Morpheus::InstancesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(options=nil)
		url = "#{@base_url}/api/instances"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers.params.merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/instances/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end


	def create(options)
		url = "#{@base_url}/api/instances"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = {instance: options}
		response = RestClient::Request.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/instances/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = RestClient::Request.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end
end