require 'json'
require 'rest-client'

class Morpheus::ServersInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(options=nil)
		url = "#{@base_url}/api/servers"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/servers/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl:false)
		JSON.parse(response.to_s)
	end

	def create(options)
		url = "#{@base_url}/api/servers"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def stop(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/stop"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def start(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/start"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def install_agent(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/install-agent"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def upgrade(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/upgrade"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def reprovision(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/reprovision"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def reinitialize(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/reinitialize"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def assign_account(serverId,payload = {})
		url = "#{@base_url}/api/servers/#{serverId}/assign-account"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers, verify_ssl:false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def workflow(id,task_set_id,payload)
		url = "#{@base_url}/api/servers/#{id}/workflow"
		headers = { :params => {:taskSetId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false,payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id, params={})
		url = "#{@base_url}/api/servers/#{id}"
		headers = { :params => params,:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 30, headers: headers, verify_ssl:false)
		JSON.parse(response.to_s)
	end

	def service_plans(params)
		url = "#{@base_url}/api/servers/service-plans"
		headers = { params: params, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers, verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def volumes(id)
		url = "#{@base_url}/api/servers/#{id}/volumes"
		headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def resize(id,payload)
		url = "#{@base_url}/api/servers/#{id}/resize"
		headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false,payload: payload.to_json)
		JSON.parse(response.to_s)
	end

end
