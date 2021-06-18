require 'morpheus/api/api_client'

class Morpheus::PriceSetsInterface < Morpheus::APIClient

  def base_path
    "/api/price-sets"
  end

  def list(params={})
    url = base_path
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

end
