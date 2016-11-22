require 'json'
require 'morpheus/rest_client'

class Morpheus::CustomInstanceTypesInterface < Morpheus::APIClient
	def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def list(options={})
    url = "#{@base_url}/api/custom-instance-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  def get(id)
    url = "#{@base_url}/api/custom-instance-types/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    response = Morpheus::RestClient.execute(method: :get, url: url,
                            timeout: 10, headers: headers, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  def create(options)
    url = "#{@base_url}/api/custom-instance-types"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    # payload[:multipart] = true
    # convert to grails params
    # it = payload.delete('instanceType') || payload.delete(:instanceType)
    # if it
    #   it.each { |k,v| payload["instanceType.#{k}"] = v }
    # end
    response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  def update(id, options)
    url = "#{@base_url}/api/custom-instance-types/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    # payload[:multipart] = true
    # convert to grails params
    # it = payload.delete('instanceType') || payload.delete(:instanceType)
    # if it
    #   it.each { |k,v| payload["instanceType.#{k}"] = v }
    # end
    response = Morpheus::RestClient.execute(method: :put, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  # NOT json, multipart file upload
  def update_logo(id, logo_file)
    url = "#{@base_url}/api/custom-instance-types/#{id}/updateLogo"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:logo] = logo_file
    payload[:multipart] = true
    response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  def destroy(id)
    url = "#{@base_url}/api/custom-instance-types/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    response = Morpheus::RestClient.execute(method: :delete, url: url,
                            timeout: 10, headers: headers, verify_ssl:false)
    JSON.parse(response.to_s)
  end

  def create_version(instance_type_id, options)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/versions"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    response = Morpheus::RestClient.execute(method: :post, url: url,
                            timeout: 10, headers: headers, payload: payload.to_json, verify_ssl:false)
    JSON.parse(response.to_s)
  end

end
