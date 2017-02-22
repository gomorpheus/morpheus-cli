require 'morpheus/api/api_client'

class Morpheus::VirtualImagesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def virtual_image_types(options={})
		url = "#{@base_url}/api/virtual-image-types"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		if options.is_a?(Hash)
			headers[:params].merge!(options)
		end
		execute(method: :get, url: url, headers: headers)
	end

	def get(options=nil)
		url = "#{@base_url}/api/v-images"
		headers = { params: {}, authorization: "Bearer #{@access_token}" }

		if options.is_a?(Hash)
			headers[:params].merge!(options)
		elsif options.is_a?(Numeric)
			url = "#{@base_url}/api/v-images/#{options}"
		elsif options.is_a?(String)
			headers[:params]['name'] = options
		end
		execute(method: :get, url: url, headers: headers)
	end

	def update(id, options)
		url = "#{@base_url}/api/v-images/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end


	def create(options)
		url = "#{@base_url}/api/v-images"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		
		payload = options
		execute(method: :post, url: url, headers: headers, payload: payload.to_json)
	end

	def destroy(id)
		url = "#{@base_url}/api/v-images/#{id}"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :delete, url: url, headers: headers)
	end

	# NOT json, multipart file upload
  def upload(id, image_file)
    url = "#{@base_url}/api/v-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:file] = image_file
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def destroy_file(id, filename)
		url = "#{@base_url}/api/v-images/#{id}/files"
		#url = "#{@base_url}/api/v-images/#{id}/files/#{filename}"
		headers = { params: {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		headers[:params][:filename] = filename
		execute(method: :delete, url: url, headers: headers)
	end

end
