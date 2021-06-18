require 'morpheus/api/api_client'

class Morpheus::PricesInterface < Morpheus::APIClient

  def base_path
    "/api/prices"
  end

  def list(params={})
    url = base_path
    if params['ids']
      url = "#{url}?#{params.delete('ids').collect {|id| "id=#{id}"}.join('&')}"
    end
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = base_path
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{base_path}/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def deactivate(id, params={})
    url = "#{base_path}/#{id}/deactivate"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers)
  end

  def list_datastores(params={})
    url = "#{base_path}/datastores"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_datastore(id, params={})
    url = "#{base_path}/datastores/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_volume_types(params={})
    url = "#{base_path}/volume-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_volume_type(id, params={})
    url = "#{base_path}/volume-types/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end
end
