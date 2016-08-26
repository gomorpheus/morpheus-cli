require 'json'
require 'rest-client'

class Morpheus::AccountsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(id)
		raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
		url = "#{@base_url}/api/accounts/#{id}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def list(options={})
		url = "#{@base_url}/api/accounts"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def create(options)
		url = "#{@base_url}/api/accounts"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def update(id, options)
		url = "#{@base_url}/api/accounts/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/accounts/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end
end
