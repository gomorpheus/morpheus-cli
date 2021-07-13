require 'morpheus/api/api_client'

class Morpheus::NetworkRoutersInterface < Morpheus::APIClient

  def list(params={})
    url = "#{@base_url}/api/networks/routers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/networks/routers/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/networks/routers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/networks/routers/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def types(params={})
    url = "#{@base_url}/api/network-router-types"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json', params: params }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def groups(params={})
    url = "#{@base_url}/api/network-router-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json', params: params }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def servers(type_id, params={})
    url = "#{@base_url}/api/network-router-types/#{type_id}/servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json', params: params }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def destroy(id, payload={})
    url = "#{@base_url}/api/networks/routers/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def create_firewall_group(router_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/firewall-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_firewall_group(router_id, group_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/firewall-groups/#{group_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy_firewall_group(router_id, group_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/firewall-groups/#{group_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def create_firewall_rule(router_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/firewall-rules"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy_firewall_rule(router_id, rule_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/firewall-rules/#{rule_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def create_route(router_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/routes"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy_route(router_id, rule_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/routes/#{rule_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def create_nat(router_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/nats"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_nat(router_id, nat_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/nats/#{nat_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy_nat(router_id, nat_id, payload={})
    url = "#{@base_url}/api/networks/routers/#{router_id}/nats/#{nat_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_permissions(router_id, payload)
    url = "#{@base_url}/api/networks/routers/#{router_id}/permissions"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end
end
