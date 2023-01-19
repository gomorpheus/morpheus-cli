require 'morpheus/api/api_client'

class Morpheus::MonitoringSettingsInterface < Morpheus::APIClient

  def base_path
    "/api/monitoring-settings"
  end

  def get(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def update(payload, params={}, headers={})
    execute(method: :put, url: "#{base_path}", payload: payload, params: params, headers: headers)
  end

  def update_service_now(payload, params={}, headers={})
    execute(method: :put, url: "#{base_path}/service-now", payload: payload, params: params, headers: headers)
  end

  def update_new_relic(payload, params={}, headers={})
    execute(method: :put, url: "#{base_path}/new-relic", payload: payload, params: params, headers: headers)
  end

end
