require 'morpheus/api/api_client'

class Morpheus::BackupSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/backup-settings"
  end

  def get(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(payload, params={})
    url = base_path
    headers = { params: params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end
end
