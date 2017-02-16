require 'json'
require 'morpheus/rest_client'

class Morpheus::GroupsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(options=nil)
		url = "#{@base_url}/api/groups"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/groups/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl:false)
		JSON.parse(response.to_s)
	end

	def create(options)
		url = "#{@base_url}/api/groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = {group: options}
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/groups/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 30, headers: headers, verify_ssl:false)
		JSON.parse(response.to_s)
	end

	def update_zones(id, options)
		url = "#{@base_url}/api/groups/#{id}/update-zones"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end
	
end
