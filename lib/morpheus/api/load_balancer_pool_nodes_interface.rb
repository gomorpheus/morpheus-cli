require 'morpheus/api/secondary_rest_interface'

class Morpheus::LoadBalancerPoolNodesInterface < Morpheus::SecondaryRestInterface

  def base_path(pool_id)
    "/api/load-balancer-pools/#{pool_id}/nodes"
  end
end
