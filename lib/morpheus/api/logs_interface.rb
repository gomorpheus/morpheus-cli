require 'morpheus/api/api_client'

class Morpheus::LogsInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def container_logs(containers=[], params={})
    url = "#{@base_url}/api/logs"
    headers = { params: {'containers' => containers}.merge(params), authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def server_logs(servers=[], params={})
    url = "#{@base_url}/api/logs"
    headers = { params: {'servers' => servers}.merge(params), authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def cluster_logs(id, params={})
    url = "#{@base_url}/api/logs"
    headers = { params: {'clusterId' => id}.merge(params), authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def stats()
    url = "#{@base_url}/api/logs/log-stats"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end


end
