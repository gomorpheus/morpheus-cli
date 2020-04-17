require 'morpheus/api/api_client'

class Morpheus::PingInterface < Morpheus::APIClient
  
  def default_timeout
    5
  end
  
  def get(params={}, http_opts={})
    url = "#{@base_url}/api/ping"
    headers = {params: params}
    execute(method: :get, url: url, headers: headers, timeout: (http_opts[:timeout] || default_timeout))
  end

end
