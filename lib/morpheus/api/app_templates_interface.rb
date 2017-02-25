require 'morpheus/api/api_client'

class Morpheus::AppTemplatesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(id)
		raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
		url = "#{@base_url}/api/app-templates/#{id}"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		execute(method: :get, url: url, headers: headers)
	end

	def list(options={})
		url = "#{@base_url}/api/app-templates"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		execute(method: :get, url: url, headers: headers)
	end

	def create(options)
		url = "#{@base_url}/api/app-templates"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :post, url: url, headers: headers, payload: payload.to_json)
	end

	def update(id, options)
		url = "#{@base_url}/api/app-templates/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	def destroy(id)
		url = "#{@base_url}/api/app-templates/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :delete, url: url, headers: headers)
	end

	def list_tiers(options={})
		url = "#{@base_url}/api/app-templates/tiers"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		execute(method: :get, url: url, headers: headers)
	end

	def list_types(options={})
		url = "#{@base_url}/api/app-templates/types"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		execute(method: :get, url: url, headers: headers)
	end
	
end
