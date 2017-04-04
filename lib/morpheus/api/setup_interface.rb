require 'morpheus/api/api_client'
# There is no authentication required for this API.
class Morpheus::SetupInterface < Morpheus::APIClient
  # def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
  #   @access_token = access_token
  #   @refresh_token = refresh_token
  #   @base_url = base_url
  #   @expires_at = expires_at
  # end

  def initialize(base_url)
    @base_url = base_url
  end

  # no JSON here, just a 200 OK 'NOTHING TO SEE HERE'
  def ping(params={}, timeout=5)
    url = "#{@base_url}/ping"
    headers = {:params => params }
    opts = {method: :get, url: url, headers: headers, timeout: timeout}
    execute(opts, false)
  end

  def check(params={}, timeout=5)
    url = "#{@base_url}/api/setup/check"
    headers = {:params => params, 'Content-Type' => 'application/json' }
    execute(method: :get, url: url, headers: headers, timeout: timeout)
  end

  def get(params={}, timeout=30)
    url = "#{@base_url}/api/setup"
    headers = {:params => params, 'Content-Type' => 'application/json' }
    execute(method: :get, url: url, headers: headers, timeout: timeout)
  end

  def init(payload={}, timeout=60)
    url = "#{@base_url}/api/setup/init"
    headers = { 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json, timeout: timeout)
  end

end
