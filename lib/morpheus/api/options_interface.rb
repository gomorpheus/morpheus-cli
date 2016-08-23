require 'json'
require 'rest-client'

class Morpheus::OptionsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def options_for_source(source,params = {})
		url = "#{@base_url}/api/options/#{source}"
		headers = { params: params, authorization: "Bearer #{@access_token}" }

		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end
end