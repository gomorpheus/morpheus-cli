require 'json'
require 'morpheus/rest_client'

class Morpheus::InstancesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(options=nil)
		url = "#{@base_url}/api/instances"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/instances/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def get_envs(id, options=nil)
		url = "#{@base_url}/api/instances/#{id}/envs"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def create_env(id, options)
		url = "#{@base_url}/api/instances/#{id}/envs"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = {envs: options}
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers,verify_ssl: false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def del_env(id, name)
		url = "#{@base_url}/api/instances/#{id}/envs/#{name}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end


	def create(options)
		url = "#{@base_url}/api/instances"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers,verify_ssl: false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/instances/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def stop(id,server=true)
		url = "#{@base_url}/api/instances/#{id}/stop"
		headers = { :params => {:server => server}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def start(id,server=true)
		url = "#{@base_url}/api/instances/#{id}/start"
		headers = { :params => {:server => server}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def restart(id,server=true)
		url = "#{@base_url}/api/instances/#{id}/restart"
		headers = { :params => {:server => server},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def workflow(id,task_set_id,payload)
		url = "#{@base_url}/api/instances/#{id}/workflow"
		headers = { :params => {:taskSetId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false,payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def backup(id,server=true)
		url = "#{@base_url}/api/instances/#{id}/backup"
		headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def firewall_disable(id)
		url = "#{@base_url}/api/instances/#{id}/security-groups/disable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def firewall_enable(id)
		url = "#{@base_url}/api/instances/#{id}/security-groups/enable"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def security_groups(id)
		url = "#{@base_url}/api/instances/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers,verify_ssl: false)
		JSON.parse(response.to_s)
	end

	def apply_security_groups(id, options)
		url = "#{@base_url}/api/instances/#{id}/security-groups"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		puts "payload #{payload}"
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers,verify_ssl: false, payload: payload.to_json)
		JSON.parse(response.to_s)
	end
	
end
