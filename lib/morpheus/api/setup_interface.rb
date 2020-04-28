require 'morpheus/api/api_client'
# There is no authentication required for this API.
class Morpheus::SetupInterface < Morpheus::APIClient

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
    execute(method: :get, url: "/api/setup", headers: headers)
  end

  #this should go away and just use 
  def check(params={}, timeout=5)
    headers = {params: params}
    execute(method: :get, url: "/api/setup/check", headers: headers, timeout: timeout)
  end

  # you can only use this successfully one time on a fresh install.
  def init(payload={})
    headers = { 'Content-Type' => 'application/json' }
    execute(method: :post, url: "/api/setup/init", headers: headers, payload: payload.to_json)
  end

  def hub_register(payload={})
    headers = { 'Content-Type' => 'application/json' }
    execute(method: :post, url: "/api/setup/hub-register", headers: headers, payload: payload.to_json)
  end

  def hub_login(payload={})
    headers = { 'Content-Type' => 'application/json' }
    execute(method: :post, url: "/api/setup/hub-login", headers: headers, payload: payload.to_json)
  end  

end
