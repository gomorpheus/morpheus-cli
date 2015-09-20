require 'json'
require 'rest-client'

class Morpheus::DeployInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end


	def get(instanceId, options=nil)
		url = "#{@base_url}/api/instances/#{instanceId}/deploy"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end


	def create(instanceId, options=nil)
		url = "#{@base_url}/api/instances/#{instanceId}/deploy"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options || {}
		response = RestClient::Request.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def list_files(id)
		url = "#{@base_url}/api/deploy/#{id}/files"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = RestClient::Request.execute(method: :get, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def upload_file(id,path,destination=nil)
		url = "#{@base_url}/api/deploy/#{id}/files"
		if !destination.empty?
			url += "/#{destination}"
		end

		headers = { :authorization => "Bearer #{@access_token}"}
		
		payload = nil
		# TODO: Setup payload to be contents of file appropriately
		response = RestClient::Request.execute(
			method: :post,
			url: url,
            headers: headers,
            timeout: -1,
            payload: {
            	multipart: true,
            	file: File.new(path, 'rb')	
        	})
		JSON.parse(response.to_s)
	end

	def destroy(id)
		url = "#{@base_url}/api/deploy/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = RestClient::Request.execute(method: :delete, url: url,
                            timeout: 10, headers: headers)
		JSON.parse(response.to_s)
	end

	def deploy(id, options)
		url = "#{@base_url}/api/deploy/#{id}/deploy"
		payload = options
		if !options[:appDeploy].nil?
			if !options[:appDeploy][:config].nil?
				options[:appDeploy][:config] = options[:appDeploy][:config].to_json
			end
		end
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = RestClient::Request.execute(method: :post, url: url, headers: headers, timeout: -1, payload: payload.to_json)
		JSON.parse(response.to_s)
	end
end