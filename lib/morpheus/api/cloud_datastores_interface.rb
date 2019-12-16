require 'morpheus/api/api_client'

class Morpheus::CloudDatastoresInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(cloud_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(cloud_id, params={})
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(cloud_id, payload)
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(cloud_id, id, payload)
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(cloud_id, id, params={})
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def selectable(cloud_id, params={})
    url = "#{@base_url}/api/zones/#{cloud_id}/data-stores/selectable"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
