require 'morpheus/api/api_client'

class Morpheus::BillingInterface < Morpheus::APIClient

  def base_path
    "/api/billing"
  end

  # this is an alias for /usage
  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def list_account(params={})
    execute(method: :get, url: "#{base_path}/account", params: params)
  end

  def list_zones(params={})
    execute(method: :get, url: "#{base_path}/zones", params: params)
  end

  def list_instances(params={})
    execute(method: :get, url: "#{base_path}/instances", params: params)
  end

  def list_servers(params={})
    execute(method: :get, url: "#{base_path}/servers", params: params)
  end

  def list_discovered_servers(params={})
    execute(method: :get, url: "#{base_path}/discoveredServers", params: params)
  end

end
