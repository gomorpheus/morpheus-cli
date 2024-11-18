require 'morpheus/api/api_client'

class Morpheus::ApplianceSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/appliance-settings"
  end

  def get()
    url = base_path
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload)
    url = base_path
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def cloud_types(params={})
    url = "#{base_path}/zone-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def locales(params={})
    url = "#{base_path}/locales"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def maintenance(params={}, payload={})
    url = "#{base_path}/maintenance"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :post, url: url, headers: headers, payload: payload}
    execute(opts)
  end

  def reindex(params={}, payload={})
    url = "#{base_path}/reindex"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :post, url: url, headers: headers, payload: payload}
    execute(opts)
  end

end
