require 'json'
require 'morpheus/rest_client'

class Morpheus::SecurityGroupRulesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(security_group_id, options=nil)
		url = "#{@base_url}/api/security-groups/#{security_group_id}/rules"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/security-groups/#{security_group_id}/rules/#{options}"
		end
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def create(security_group_id, options)
		url = "#{@base_url}/api/security-groups/#{security_group_id}/rules"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def delete(security_group_id, id)
		url = "#{@base_url}/api/security-groups/#{security_group_id}/rules/#{id}"
		print "url #{url}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end
end
