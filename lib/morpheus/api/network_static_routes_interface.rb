require 'morpheus/api/api_client'

class Morpheus::NetworkStaticRoutesInterface < Morpheus::RestInterface

  def base_path
    "/api/networks"
  end

  def get_static_route(network_id, route_id, params={}, headers={})
    validate_id!(network_id)
    validate_id!(route_id)
    execute(method: :get, url: "#{base_path}/#{network_id}/routes/#{route_id}", params: params, headers: headers)
  end

  def list_static_routes(network_id, params={}, headers={})
    validate_id!(network_id)
    execute(method: :get, url: "#{base_path}/#{network_id}/routes", params: params, headers: headers)
  end

  def create_static_route(network_id, payload, params={}, headers={})
    validate_id!(network_id)
    execute(method: :post, url: "#{base_path}/#{network_id}/routes", params: params, payload: payload, headers: headers)
  end

  def update_static_route(network_id, route_id, payload, params={}, headers={})
    validate_id!(network_id)
    validate_id!(route_id)
    execute(method: :put, url: "#{base_path}/#{network_id}/routes/#{route_id}", params: params, payload: payload, headers: headers)
  end

  def delete_static_route(network_id, route_id, params={}, headers={})
    validate_id!(network_id)
    validate_id!(route_id)
    execute(method: :delete, url: "#{base_path}/#{network_id}/routes/#{route_id}", params: params, headers: headers)
  end
end
