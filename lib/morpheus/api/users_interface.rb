require 'json'
require 'rest-client'

class Morpheus::UsersInterface < Morpheus::APIClient
	
	def initialize(access_token, refresh_token, expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(account_id, id)
		raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
		url = build_url(account_id, id)
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def list(account_id, options={})
		url = build_url(account_id)
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def feature_permissions(account_id, id)
		url = build_url(account_id, id) + "/feature-permissions"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def available_roles(account_id, id=nil, options={})
		url = build_url(account_id, id) + "/available-roles"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def create(account_id, options)
		url = build_url(account_id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def update(account_id, id, options)
		url = build_url(account_id, id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(account_id, id)
		url = build_url(account_id, id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

private

	def build_url(account_id=nil, user_id=nil)
		url = "#{@base_url}/api"
		if account_id
			url += "/accounts/#{account_id}/users"
		else
			url += "/users"
		end
		if user_id
			url += "/#{user_id}"
		end
		url
	end

end
