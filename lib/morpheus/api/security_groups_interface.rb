require 'json'
require 'rest-client'

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
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def get(options)
		url = "#{@base_url}/api/security-groups/#{options[:id]}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		if options.is_a?(Hash)
			headers[:params].merge!(options)
		end
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def create(options)
		url = "#{@base_url}/api/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = RestClient::Request.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def update(id)
		url = "#{@base_url}/api/security-groups/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = RestClient::Request.execute(method: :put, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def delete(id)
		url = "#{@base_url}/api/security-groups/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = RestClient::Request.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end
end