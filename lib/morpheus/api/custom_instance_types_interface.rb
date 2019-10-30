require 'morpheus/api/api_client'

class Morpheus::CustomInstanceTypesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def list(params={})
    url = "#{@base_url}/api/custom-instance-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id)
    url = "#{@base_url}/api/custom-instance-types/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
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
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
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
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  # NOT json, multipart file upload
  def update_logo(id, logo_file)
    url = "#{@base_url}/api/custom-instance-types/#{id}/update-logo"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:logo] = logo_file
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def destroy(id)
    url = "#{@base_url}/api/custom-instance-types/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def create_version(instance_type_id, options)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/versions"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_version(instance_type_id, id, options)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/versions/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_version(instance_type_id, id)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/versions/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :delete, url: url, headers: headers)
  end

  def create_upgrade(instance_type_id, options)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/upgrades"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_upgrade(instance_type_id, id, options)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/upgrades/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_upgrade(instance_type_id, id)
    url = "#{@base_url}/api/custom-instance-types/#{instance_type_id}/upgrades/#{id}"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json'}
    payload = options
    execute(method: :delete, url: url, headers: headers)
  end

end
