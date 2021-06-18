require 'morpheus/api/api_client'

class Morpheus::LogsInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/logs"
    # old versions expected containers[]
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def container_logs(containers=[], params={})
    url = "#{@base_url}/api/logs"
    # old versions expected containers[]
    headers = { params: {'containers' => containers, 'containers[]' => containers}.merge(params), authorization: "Bearer #{@access_token}" }
    execute({method: :get, url: url, headers: headers})
  end

  def server_logs(servers=[], params={})
    url = "#{@base_url}/api/logs"
    # old versions expected containers[]
    headers = { params: {'servers' => servers, 'servers[]' => servers}.merge(params), authorization: "Bearer #{@access_token}" }
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
