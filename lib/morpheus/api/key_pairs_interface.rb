require 'morpheus/api/api_client'

class Morpheus::KeyPairsInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(account_id, id)
		raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
		url = "#{@base_url}/api/key-pairs/#{id}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params]['accountId'] = account_id if account_id
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def list(account_id, options={})
		url = "#{@base_url}/api/key-pairs"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		headers[:params]['accountId'] = account_id if account_id
		opts = {method: :get, url: url, headers: headers}
		execute(opts)
	end

	def create(account_id, options)
		url = "#{@base_url}/api/key-pairs"
		headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		headers[:params]['accountId'] = account_id if account_id
		payload = options
		opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def update(account_id, id, options)
		url = "#{@base_url}/api/key-pairs/#{id}"
		headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		headers[:params]['accountId'] = account_id if account_id
		payload = options
		opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
		execute(opts)
	end

	def destroy(account_id, id)
		url = "#{@base_url}/api/key-pairs/#{id}"
		headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		headers[:params]['accountId'] = account_id if account_id
		opts = {method: :delete, url: url, headers: headers}
		execute(opts)
	end
end
