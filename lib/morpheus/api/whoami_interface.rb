require 'morpheus/api/api_client'

class Morpheus::WhoamiInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get()
		url = "#{@base_url}/api/whoami"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		execute(method: :get, url: url, headers: headers)
	end

end
