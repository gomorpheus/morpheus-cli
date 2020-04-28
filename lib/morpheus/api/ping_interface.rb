require 'morpheus/api/api_client'

class Morpheus::PingInterface < Morpheus::APIClient
  
  # no Authorization header is required
  def authorization_required?
    false
  end

  # health checks use a relatively small timeout by default
  def default_timeout
    5
  end

  def get(params={})
    headers = {params: params}
    execute(method: :get, url: "/api/ping", headers: headers)
  end

end
