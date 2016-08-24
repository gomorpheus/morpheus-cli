require 'json'
require 'net/http/post/multipart'
require 'mime/types'
require 'morpheus/rest_client'

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
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end


	def create(instanceId, options=nil)
		url = "#{@base_url}/api/instances/#{instanceId}/deploy"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options || {}
		response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 30, headers: headers, payload: payload.to_json)
		JSON.parse(response.to_s)
	end

	def list_files(id)
		url = "#{@base_url}/api/deploy/#{id}/files"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 30, headers: headers)
		JSON.parse(response.to_s)
	end

	def upload_file(id,path,destination=nil)
		url_string = "#{@base_url}/api/deploy/#{id}/files"
		if !destination.empty?
			url_string += "/#{destination}"
		end

		url = URI.parse(url_string)
		req = Net::HTTP::Post::Multipart.new url.path,
		  "file" => UploadIO.new(File.new(path,'rb'), "image/jpeg", File.basename(path))

		  req['Authorization'] = "Bearer #{@access_token}"
		res = Net::HTTP.start(url.host, url.port) do |http|
		  http.request(req)
		end
		
		res
	end

	def destroy(id)
		url = "#{@base_url}/api/deploy/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 30, headers: headers)
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
		response = Morpheus::RestClient.execute(method: :post, url: url, headers: headers, timeout: nil, payload: payload.to_json)
		JSON.parse(response.to_s)
	end
end
