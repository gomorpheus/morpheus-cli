require 'morpheus/api/api_client'

class Morpheus::GuidanceSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/guidance-settings"
  end

  def get(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def update(payload, params={}, headers={})
    execute(method: :put, url: "#{base_path}", payload: payload, params: params, headers: headers)
  end

end
