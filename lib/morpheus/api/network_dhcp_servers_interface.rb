require 'morpheus/api/api_client'

class Morpheus::NetworkDhcpServersInterface < Morpheus::RestInterface

  def base_path
    "/api/networks/servers"
  end

  def get_dhcp_server(server_id, dhcp_server_id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(dhcp_server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/dhcp-servers/#{dhcp_server_id}", params: params, headers: headers)
  end

  def list_dhcp_servers(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/dhcp-servers", params: params, headers: headers)
  end

  def create_dhcp_server(server_id, payload, params={}, headers={})
    validate_id!(server_id)
    execute(method: :post, url: "#{base_path}/#{server_id}/dhcp-servers", params: params, payload: payload, headers: headers)
  end

  def update_dhcp_server(server_id, dhcp_server_id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(dhcp_server_id)
    execute(method: :put, url: "#{base_path}/#{server_id}/dhcp-servers/#{dhcp_server_id}", params: params, payload: payload, headers: headers)
  end

  def delete_dhcp_server(server_id, dhcp_server_id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(dhcp_server_id)
    execute(method: :delete, url: "#{base_path}/#{server_id}/dhcp-servers/#{dhcp_server_id}", params: params, headers: headers)
  end
end
