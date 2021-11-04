require 'morpheus/api/api_client'

class Morpheus::NetworkServersInterface < Morpheus::RestInterface

  def base_path
    "/api/networks/servers"
  end

  def list_scopes(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/scopes", params: params, headers: headers)
  end

  def get_scope(server_id, scope_id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(scope_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/scopes/#{scope_id}", params: params, headers: headers)
  end

  def create_scope(server_id, payload, params={}, headers={})
    validate_id!(server_id)
    execute(method: :post, url: "#{base_path}/#{server_id}/scopes", params: params, payload: payload, headers: headers)
  end

  def update_scope(server_id, scope_id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(scope_id)
    execute(method: :put, url: "#{base_path}/#{server_id}/scopes/#{scope_id}", params: params, payload: payload, headers: headers)
  end

  def destroy_scope(server_id, scope_id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(scope_id)
    execute(method: :delete, url: "#{base_path}/#{server_id}/scopes/#{scope_id}", params: params, headers: headers)
  end

  def update_scope_permissions(server_id, scope_id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(scope_id)
    execute(method: :put, url: "#{base_path}/#{server_id}/scopes/#{scope_id}", payload: payload.to_json, params: params, headers: headers)
  end
end
