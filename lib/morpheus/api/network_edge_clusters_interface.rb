require 'morpheus/api/api_client'

class Morpheus::NetworkEdgeClustersInterface < Morpheus::RestInterface

  def base_path
    "/api/networks/servers"
  end

  def list_edge_clusters(server_id, params={}, headers={})
    validate_id!(server_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/edge-clusters", params: params, headers: headers)
  end

  def get_edge_cluster(server_id, edge_cluster_id, params={}, headers={})
    validate_id!(server_id)
    validate_id!(edge_cluster_id)
    execute(method: :get, url: "#{base_path}/#{server_id}/edge-clusters/#{edge_cluster_id}", params: params, headers: headers)
  end

  def update_edge_cluster(server_id, edge_cluster_id, payload, params={}, headers={})
    validate_id!(server_id)
    validate_id!(edge_cluster_id)
    execute(method: :put, url: "#{base_path}/#{server_id}/edge-clusters/#{edge_cluster_id}", params: params, payload: payload, headers: headers)
  end

end
