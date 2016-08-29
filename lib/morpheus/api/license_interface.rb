require 'json'
require 'rest-client'

class Morpheus::LicenseInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get()
		url = "#{@base_url}/api/license"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def apply(key)
		url = "#{@base_url}/api/license"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = {license: key}
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers, payload: payload.to_json, verify_ssl: false)
		JSON.parse(response.to_s)
	end

end
