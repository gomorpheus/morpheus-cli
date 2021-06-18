require 'morpheus/api/api_client'

class Morpheus::ProvisioningSettingsInterface < Morpheus::APIClient
  
  def base_path
    "/api/provisioning-settings"
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

  def template_types()
    url = "#{base_path}/template-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end
end
