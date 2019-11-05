require 'morpheus/api/api_client'

class Morpheus::BackupSettingsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil, api='backup-settings')
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @api_url = "#{base_url}/api/#{api}"
    @expires_at = expires_at
  end

  def get(params={})
    url = @api_url
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = @api_url
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end
end
