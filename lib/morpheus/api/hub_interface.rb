require 'morpheus/api/api_client'

class Morpheus::HubInterface < Morpheus::APIClient

  def base_path
    "/api/hub"
  end

  def get(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def usage(params={}, headers={})
    execute(method: :get, url: "#{base_path}/usage", params: params, headers: headers)
  end

  def checkin(payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/checkin", payload: payload, params: params, headers: headers)
  end

  def register(payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/register", payload: payload, params: params, headers: headers)
  end

end
