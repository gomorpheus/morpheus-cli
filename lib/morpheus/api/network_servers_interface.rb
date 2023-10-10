require 'morpheus/api/api_client'

class Morpheus::NetworkServersInterface < Morpheus::RestInterface

  def base_path
    "/api/networks/servers"
  end

  def refresh(id, params={}, payload={}, headers={})
    execute(method: :post, url: "#{base_path}/#{id}/refresh", params: params, payload: payload, headers: headers)
  end

  def list_scopes(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/scopes", params: params, headers: headers)
  end

  def get_scope(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{server_id}/scopes/#{id}", params: params, headers: headers)
  end

  def create_scope(server_id, payload, params={}, headers={})
    validate_id!(server_id)
    execute(method: :post, url: "#{base_path}/#{server_id}/scopes", params: params, payload: payload, headers: headers)
  end

  def update_scope(server_id, id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{server_id}/scopes/#{id}", params: params, payload: payload, headers: headers)
  end

  def destroy_scope(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{server_id}/scopes/#{id}", params: params, headers: headers)
  end

  def update_scope_permissions(server_id, id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{server_id}/scopes/#{id}", payload: payload.to_json, params: params, headers: headers)
  end

  def list_firewall_rules(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/firewall-rules", params: params, headers: headers)
  end

  def get_firewall_rule(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{server_id}/firewall-rules/#{id}", params: params, headers: headers)
  end

  def create_firewall_rule(server_id, payload, params={}, headers={})
    validate_id!(server_id)
    execute(method: :post, url: "#{base_path}/#{server_id}/firewall-rules", params: params, payload: payload, headers: headers)
  end

  def update_firewall_rule(server_id, id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{server_id}/firewall-rules/#{id}", params: params, payload: payload, headers: headers)
  end

  def destroy_firewall_rule(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{server_id}/firewall-rules/#{id}", params: params, headers: headers)
  end

  def list_firewall_rule_groups(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/firewall-rule-groups", params: params, headers: headers)
  end

  def get_firewall_rule_group(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{server_id}/firewall-rule-groups/#{id}", params: params, headers: headers)
  end

  def create_firewall_rule_group(server_id, payload, params={}, headers={})
    validate_id!(server_id)
    execute(method: :post, url: "#{base_path}/#{server_id}/firewall-rule-groups", params: params, payload: payload, headers: headers)
  end

  def update_firewall_rule_group(server_id, id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{server_id}/firewall-rule-groups/#{id}", params: params, payload: payload, headers: headers)
  end

  def destroy_firewall_rule_group(server_id, id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{server_id}/firewall-rule-groups/#{id}", params: params, headers: headers)
  end
end
