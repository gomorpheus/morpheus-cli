require 'morpheus/api/api_client'

class Morpheus::IntegrationsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='integrations')
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @api_url = "#{base_url}/api/#{api}"
    @expires_at = expires_at
  end

  def list(params={})
    url = @api_url
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(id, params={})
    url = "#{@api_url}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = @api_url
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end
end
