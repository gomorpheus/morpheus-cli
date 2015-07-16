require 'json'
require 'rest-client'

class Morpheus::InstanceTypesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(options=nil)
		url = "#{@base_url}/api/instance-types"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/instance-types/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def service_plans(layout_id, name=nil)
		url = "#{@base_url}/api/instance-types/service-plans/#{layout_id}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if !name.nil?
			headers[:params][:name] = name
		end
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end


end