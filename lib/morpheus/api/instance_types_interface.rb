require 'json'
require 'morpheus/rest_client'

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
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl:false)
		JSON.parse(response.to_s)
	end

	def service_plans(layout_id, name=nil)
		url = "#{@base_url}/api/instance-types/service-plans/#{layout_id}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if !name.nil?
			headers[:params][:name] = name
		end
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def service_plan_options(service_plan_id, params)
		url = "#{@base_url}/api/instance-types/service-plans/#{service_plan_id}/options"
		headers = { params: params, authorization: "Bearer #{@access_token}" }

		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl: false)
		JSON.parse(response.to_s)
	end


end
