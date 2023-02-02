require 'morpheus/api/api_client'

class Morpheus::CloudResourcePoolsInterface < Morpheus::APIClient

  def get(cloud_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = cloud_id.nil? ? "#{@base_url}/api/zones/resource-pools/#{update_resource_pool_id(id)}" : "#{@base_url}/api/zones/#{cloud_id}/resource-pools/#{update_resource_pool_id(id)}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get_without_cloud(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/resource-pools/#{update_resource_pool_id(id)}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(cloud_id, params={})
    url = cloud_id.nil? ? "#{@base_url}/api/zones/resource-pools" : "#{@base_url}/api/zones/#{cloud_id}/resource-pools"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_without_cloud(params={})
    url = "#{@base_url}/api/resource-pools"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(cloud_id, payload)
    url = "#{@base_url}/api/zones/#{cloud_id}/resource-pools"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(cloud_id, id, payload)
    url = "#{@base_url}/api/zones/#{cloud_id}/resource-pools/#{update_resource_pool_id(id)}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(cloud_id, id, params={})
    url = "#{@base_url}/api/zones/#{cloud_id}/resource-pools/#{update_resource_pool_id(id)}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  private

  def update_resource_pool_id(id)
    id_string = id.to_s
    if id_string["pool-"]
      return id_string[5..-1]
    end
    return id
  end

end
