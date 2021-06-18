require 'morpheus/api/api_client'

class Morpheus::BlueprintsInterface < Morpheus::APIClient
  
  def get(id)
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/blueprints/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list(params={})
    url = "#{@base_url}/api/blueprints"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = "#{@base_url}/api/blueprints"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@base_url}/api/blueprints/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_permissions(id, payload)
    url = "#{@base_url}/api/blueprints/#{id}/update-permissions"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  # multipart image upload
  def save_image(id, image_file, params={})
    url = "#{@base_url}/api/blueprints/#{id}/image"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:templateImage] = image_file
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def duplicate(id, payload)
    url = "#{@base_url}/api/blueprints/#{id}/duplicate"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id)
    url = "#{@base_url}/api/blueprints/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def list_tiers(payload={})
    url = "#{@base_url}/api/blueprints/tiers"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_types(params={})
    url = "#{@base_url}/api/blueprints/types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

end
